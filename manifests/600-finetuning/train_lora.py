"""
LoRA Fine-tuning script for AnyVC (Venture Capital Advisor)
Base model: Ministral-3-8B-Instruct-2512
Runs on a single NVIDIA L40S GPU (g6e.2xlarge, 48GB VRAM)
"""

import os
import sys
import json
import torch
from datasets import Dataset
from transformers import (
    AutoTokenizer,
    FineGrainedFP8Config,
    Mistral3ForConditionalGeneration,
    TrainingArguments,
)
from peft import LoraConfig, get_peft_model
from trl import SFTTrainer

MODEL_PATH = os.getenv("MODEL_PATH", "/models/Ministral-3-8B-Instruct-2512")
DATASET_PATH = os.getenv("DATASET_PATH", "/data/anyvc-startup-dataset.jsonl")
OUTPUT_DIR = os.getenv("OUTPUT_DIR", "/output/anyvc-startup-lora")
S3_OUTPUT_PATH = os.getenv("S3_OUTPUT_PATH", "")
NUM_EPOCHS = int(os.getenv("NUM_EPOCHS", "10"))
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "2"))
GRADIENT_ACCUMULATION = int(os.getenv("GRADIENT_ACCUMULATION", "2"))
LEARNING_RATE = float(os.getenv("LEARNING_RATE", "2e-4"))
MAX_SEQ_LENGTH = int(os.getenv("MAX_SEQ_LENGTH", "1024"))
LORA_RANK = int(os.getenv("LORA_RANK", "16"))
LORA_ALPHA = int(os.getenv("LORA_ALPHA", "32"))
HF_MODEL_ID = os.getenv("HF_MODEL_ID", "mistralai/Ministral-3-8B-Instruct-2512")

print("=" * 60)
print("  LoRA Fine-tuning: AnyVC Startup Advisor")
print("=" * 60)
print(f"  Model path:        {MODEL_PATH}")
print(f"  Dataset:           {DATASET_PATH}")
print(f"  Output:            {OUTPUT_DIR}")
print(f"  Epochs:            {NUM_EPOCHS}")
print(f"  Batch (effective): {BATCH_SIZE * GRADIENT_ACCUMULATION}")
print(f"  LoRA rank/alpha:   {LORA_RANK}/{LORA_ALPHA}")
print("=" * 60)

# Step 1: Validate
print("\n[1/8] Validating model files...")
model_files = os.listdir(MODEL_PATH)
print(f"  Found: {sorted(model_files)}")

# Step 2: Load dataset
print("\n[2/8] Loading dataset...")
records = []
with open(DATASET_PATH, "r") as f:
    for line in f:
        line = line.strip()
        if line:
            records.append(json.loads(line))
dataset = Dataset.from_list(records)
print(f"  Loaded {len(dataset)} training examples")

# Step 3: Load tokenizer
print("\n[3/8] Loading tokenizer...")
try:
    from transformers import MistralCommonBackend
    tokenizer = MistralCommonBackend.from_pretrained(MODEL_PATH, local_files_only=True, mode="finetuning")
    print("  Using MistralCommonBackend tokenizer")
except Exception as e:
    print(f"  Fallback to AutoTokenizer ({e})")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH, trust_remote_code=True, local_files_only=True)

if tokenizer.pad_token is None:
    tokenizer.pad_token = tokenizer.eos_token
    tokenizer.pad_token_id = tokenizer.eos_token_id
tokenizer.padding_side = "right"

# Step 4: Load model
print("\n[4/8] Loading model (FP8 → BF16)...")
model = Mistral3ForConditionalGeneration.from_pretrained(
    HF_MODEL_ID,
    quantization_config=FineGrainedFP8Config(dequantize=True),
    device_map="auto",
    trust_remote_code=True,
    attn_implementation="eager",
)
model.gradient_checkpointing_enable(gradient_checkpointing_kwargs={"use_reentrant": False})
for param in model.parameters():
    param.requires_grad = False
total_params = sum(p.numel() for p in model.parameters())
print(f"  Parameters: {total_params/1e9:.1f}B | GPU: {torch.cuda.memory_allocated()/1e9:.1f} GB")

# Step 5: LoRA
print("\n[5/8] Attaching LoRA adapters...")
lora_config = LoraConfig(
    r=LORA_RANK, lora_alpha=LORA_ALPHA,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
    lora_dropout=0.05, bias="none", task_type="CAUSAL_LM",
)
model = get_peft_model(model, lora_config)
trainable = sum(p.numel() for p in model.parameters() if p.requires_grad)
print(f"  Trainable: {trainable/1e6:.1f}M ({100*trainable/total_params:.2f}%)")

# Step 6: Format
print("\n[6/8] Formatting dataset...")
def format_chat(example):
    try:
        text = tokenizer.apply_chat_template(example["messages"], tokenize=False, add_generation_prompt=False)
    except Exception:
        text = "<s>"
        for msg in example["messages"]:
            if msg["role"] == "user":
                text += f"[INST] {msg['content']} [/INST]"
            elif msg["role"] == "assistant":
                text += f" {msg['content']}</s>"
    return {"text": text}

dataset = dataset.map(format_chat)

# Step 7: Train
print("\n[7/8] Training...")
training_args = TrainingArguments(
    output_dir=OUTPUT_DIR, num_train_epochs=NUM_EPOCHS,
    per_device_train_batch_size=BATCH_SIZE, gradient_accumulation_steps=GRADIENT_ACCUMULATION,
    learning_rate=LEARNING_RATE, warmup_steps=2, logging_steps=1,
    save_strategy="epoch", bf16=True, optim="adamw_torch", report_to="none", seed=42,
)
trainer = SFTTrainer(model=model, args=training_args, train_dataset=dataset, processing_class=tokenizer)
result = trainer.train()

# Step 8: Save & upload
print(f"\n[8/8] Saving adapter...")
model.save_pretrained(OUTPUT_DIR)
tokenizer.save_pretrained(OUTPUT_DIR)

from safetensors.torch import load_file, save_file
adapter_path = os.path.join(OUTPUT_DIR, "adapter_model.safetensors")
tensors = load_file(adapter_path)
fixed = {k.replace("model.model.language_model.", "model.language_model.model."): v for k, v in tensors.items()}
save_file(fixed, adapter_path)

import glob
adapter_files = [f for f in glob.glob(os.path.join(OUTPUT_DIR, "*")) if os.path.isfile(f)]
total_size = sum(os.path.getsize(f) for f in adapter_files)
print(f"  Loss: {result.training_loss:.4f} | Runtime: {result.metrics['train_runtime']:.0f}s | Size: {total_size/1024/1024:.1f} MB")

if S3_OUTPUT_PATH:
    import boto3
    s3_parts = S3_OUTPUT_PATH.replace("s3://", "").rstrip("/").split("/", 1)
    bucket, prefix = s3_parts[0], (s3_parts[1] + "/") if len(s3_parts) > 1 else ""
    s3 = boto3.client("s3")
    for f in sorted(adapter_files):
        s3.upload_file(f, bucket, prefix + os.path.basename(f))
    print(f"  Uploaded to {S3_OUTPUT_PATH}")

print("\nDone! Serve with vLLM --enable-lora")
