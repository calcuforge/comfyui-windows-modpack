# -*- coding: utf-8 -*-
"""Windows patches for the ComfyUI_IndexTTS custom node.

1. indexttsnode.py: the non-fp16 path hardcodes use_deepspeed=True, which
   crashes on Windows (deepspeed cannot be built there) -> force False so the
   plain .eval() inference path is used.
2. front.py: the 'tn' text normalizer (WeTextProcessing) depends on pynini,
   which has no Windows wheels. Wrap the import so the node falls back to raw
   text instead of raising on load.

Idempotent: each replacement is applied only if not already present.
"""
import io
import os

NODE_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ComfyUI", "custom_nodes", "ComfyUI_IndexTTS"))
NODE_PY = os.path.join(NODE_DIR, "indexttsnode.py")
FRONT_PY = os.path.join(NODE_DIR, "indextts", "utils", "front.py")


def patch(path, old, new, label):
    if not os.path.exists(path):
        print(f"[patch] skip {label}: file missing ({path})")
        return
    with io.open(path, encoding="utf-8") as f:
        text = f.read()
    if new in text:
        print(f"[patch] skip {label}: already applied")
        return
    if old not in text:
        print(f"[patch] WARNING {label}: anchor not found, skipping")
        return
    with io.open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text.replace(old, new))
    print(f"[patch] applied {label}")


patch(
    NODE_PY,
    "post_init_gpt2_config(use_deepspeed=True, kv_cache=True, half=False)",
    "post_init_gpt2_config(use_deepspeed=False, kv_cache=True, half=False)",
    "deepspeed fallback (indexttsnode.py)",
)

OLD_TN = (
    "            from tn.chinese.normalizer import Normalizer as NormalizerZh\n"
    "            from tn.english.normalizer import Normalizer as NormalizerEn\n"
)
NEW_TN = (
    "            try:\n"
    "                from tn.chinese.normalizer import Normalizer as NormalizerZh\n"
    "                from tn.english.normalizer import Normalizer as NormalizerEn\n"
    "            except ImportError:\n"
    "                def NormalizerZh(*a, **k):\n"
    "                    return None\n"
    "\n"
    "                def NormalizerEn(*a, **k):\n"
    "                    return None\n"
)
patch(FRONT_PY, OLD_TN, NEW_TN, "tn normalizer import fallback (front.py)")

OLD_RAW = (
    '            print("Error, text normalizer is not initialized !!!")\n'
    '            return ""\n'
)
NEW_RAW = (
    '            print("Warning: text normalizer is not initialized, using raw text")\n'
    "            return text\n"
)
patch(FRONT_PY, OLD_RAW, NEW_RAW, "tn normalizer raw-text fallback (front.py)")
