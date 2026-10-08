"""Validate fixed-width USER3 dependency paths and immutable publication."""
from pathlib import Path
import tempfile, unittest
from native_model_loader import loader_bytes,ensure_loader,TEMPLATE_ID,template

class LoaderTests(unittest.TestCase):
    def test_paths_offsets_and_id(self):
        asset='section_0123456789abcdef0123';data=loader_bytes(asset)
        self.assertEqual(len(data),len(template()))
        self.assertEqual(data.count(asset.encode('utf-16le')),8)
        self.assertNotIn(TEMPLATE_ID.encode('utf-16le'),data)
        for suffix in ('.mesh','.mdf2'):
            path=f'mod/onimusha_mc/sections/{asset}/{asset}{suffix}'.encode('utf-16le')
            self.assertEqual(data.count(path),2)
        for bad in ('../bad','section_'+'f'*19,'section_'+'a'*21):
            with self.assertRaises(ValueError):loader_bytes(bad)
    def test_no_overwrite(self):
        with tempfile.TemporaryDirectory() as d:
            folder=Path(d);asset='section_12345678901234567890'
            first=ensure_loader(folder,asset)
            self.assertEqual(first,ensure_loader(folder,asset))
            (folder/first[0]).write_bytes(b'foreign')
            with self.assertRaises(ValueError):ensure_loader(folder,asset)
            self.assertEqual((folder/first[0]).read_bytes(),b'foreign')

if __name__=='__main__':unittest.main()
