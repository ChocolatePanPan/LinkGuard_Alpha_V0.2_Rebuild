"""
Shared pytest fixtures and sys.path configuration for win11 tests.
"""
import sys
import os

# Ensure the win11 directory is on sys.path so all modules can be imported.
WIN11_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if WIN11_DIR not in sys.path:
    sys.path.insert(0, WIN11_DIR)
