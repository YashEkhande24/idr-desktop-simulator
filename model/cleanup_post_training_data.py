#!/usr/bin/env python3
import os
import shutil

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
POST_TRAIN_DIR = os.path.join(SCRIPT_DIR, "datasets", "post_training")

if os.path.exists(POST_TRAIN_DIR):
    shutil.rmtree(POST_TRAIN_DIR)
    print(f"[OK] Cleaned up post-training dataset directory: {POST_TRAIN_DIR}")
else:
    print(f"[INFO] Post-training directory does not exist: {POST_TRAIN_DIR}")
