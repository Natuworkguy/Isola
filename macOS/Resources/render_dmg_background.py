"""Renders DMGBackground.html to DMGBackground.png and DMGBackground@2x.png, the installer window's background.

    pip install playwright && playwright install chromium
    python3 macOS/Resources/render_dmg_background.py

CHROMIUM=/path/to/chrome uses that browser instead of Playwright's own.
"""

import os
from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=os.environ.get("CHROMIUM") or None)
    for scale, name in ((1, "DMGBackground.png"), (2, "DMGBackground@2x.png")):
        page = browser.new_page(viewport={"width": 660, "height": 440}, device_scale_factor=scale)
        page.goto((HERE / "DMGBackground.html").as_uri(), wait_until="networkidle")
        page.evaluate("document.fonts.ready")
        page.screenshot(path=str(HERE / name))
        page.close()
    browser.close()
