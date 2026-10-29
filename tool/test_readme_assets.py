"""Validate repo-owned README UI preview assets using hardened XML parsing."""

from io import BytesIO
from pathlib import Path
import re
import unittest
from defusedxml import ElementTree
from defusedxml.common import DTDForbidden

ROOT = Path(__file__).resolve().parents[1]


def parse_svg(source):
    # README previews never need DTDs or entity expansion.
    return ElementTree.parse(source, forbid_dtd=True).getroot()


class ReadmePreviewTests(unittest.TestCase):
    def test_readme_preview_images_exist_and_are_valid_svg(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        references = re.findall(r"!\[[^\]]*\]\(([^)]+)\)", readme)
        self.assertGreaterEqual(len(references), 2, "README needs phone and tablet/watch images")
        self.assertIn("fictional", readme.lower())
        self.assertIn("concept", readme.lower())

        for reference in references:
            with self.subTest(reference=reference):
                self.assertFalse(reference.startswith(("http:", "https:")))
                target = (ROOT / reference).resolve()
                self.assertTrue(target.is_relative_to(ROOT.resolve()))
                self.assertTrue(target.is_file(), f"Missing preview: {reference}")
                self.assertEqual(target.suffix, ".svg")
                xml = parse_svg(target)
                self.assertEqual(xml.tag, "{http://www.w3.org/2000/svg}svg")
                self.assertIn("viewBox", xml.attrib)
                self.assertTrue(any(
                    element.tag.endswith("title") and (element.text or "").strip()
                    for element in xml.iter()
                ), f"No accessible SVG title in {reference}")
                self.assertFalse(any(
                    element.tag.endswith("script") for element in xml.iter()
                ), f"SVG scripts are not allowed in {reference}")

    def test_svg_parser_rejects_doctype_and_entities(self):
        malicious_svg = b'<!DOCTYPE svg [<!ENTITY unsafe "expanded">]><svg>&unsafe;</svg>'
        with self.assertRaises(DTDForbidden):
            parse_svg(BytesIO(malicious_svg))


if __name__ == "__main__":
    unittest.main()
