import hashlib,json,tempfile,unittest
from pathlib import Path
from native_model_cache import ModelCache

class Cache(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.atlas=self.root/'atlas.bin';self.atlas.write_bytes(b'actual rgba')
        self.cache=ModelCache(self.root,'converter-v1')
        self.asset='section_'+'1'*20
        (self.root/self.asset).mkdir();self.files={}
        for ext in ('.mesh.260209350','.mdf2.51','.tex.251111100'):
            name=self.asset+ext;data=ext.encode();(self.root/self.asset/name).write_bytes(data)
            self.files[name]=hashlib.sha256(data).hexdigest()
        self.key=self.cache.key(b'model vertices',self.atlas,[])
    def test_restart_reuses_content_without_session_identity(self):
        self.assertTrue(self.cache.store(self.key,self.asset,self.files,{'triangles':12}))
        restarted=ModelCache(self.root,'converter-v1')
        self.assertEqual(restarted.key(b'model vertices',self.atlas,[]),self.key)
        self.assertEqual(restarted.load(self.key)['asset_id'],self.asset)
    def test_model_texture_rules_flash_or_animation_change_is_miss(self):
        keys=[self.cache.key(b'new geometry',self.atlas,[]),
              self.cache.key(b'model vertices',self.atlas,[],True),
              self.cache.key(b'model vertices',self.atlas,[[0,0,16,16]]),
              ModelCache(self.root,'converter-v2').key(b'model vertices',self.atlas,[])]
        self.atlas.write_bytes(b'resource pack changed')
        keys.append(self.cache.key(b'model vertices',self.atlas,[]))
        self.assertNotIn(self.key,keys);self.assertEqual(len(set(keys)),len(keys))
    def test_missing_corrupt_and_foreign_paths_cannot_be_loaded(self):
        self.cache.store(self.key,self.asset,self.files,{})
        tex=self.root/self.asset/(self.asset+'.tex.251111100');tex.write_bytes(b'corrupt')
        self.assertIsNone(ModelCache(self.root,'converter-v1').load(self.key))
        tex.unlink();self.assertIsNone(self.cache.load(self.key))
        index=self.cache.index/(self.key+'.json');value=json.loads(index.read_text())
        value['asset_id']='../outside';index.write_text(json.dumps(value))
        self.assertIsNone(self.cache.load(self.key))
        index.write_text('{');self.assertIsNone(self.cache.load(self.key))
    def test_incomplete_publish_is_not_indexed(self):
        with self.assertRaises(ValueError):self.cache.store(self.key,self.asset,{}, {})
        self.assertFalse((self.cache.index/(self.key+'.json')).exists())

if __name__=='__main__':unittest.main()
