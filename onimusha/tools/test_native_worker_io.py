import ctypes
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from native_worker_io import atomic_json,completed_result,queued_requests


class WorkerIO(unittest.TestCase):
    def test_windows_reader_lock_retries_without_partial_json(self):
        k=ctypes.WinDLL('kernel32',use_last_error=True)
        k.CreateFileW.restype=ctypes.c_void_p
        k.CreateFileW.argtypes=[ctypes.c_wchar_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p]
        k.CloseHandle.argtypes=[ctypes.c_void_p]
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)/'worker.json';self.assertTrue(atomic_json(p,{'version':1}))
            h=k.CreateFileW(str(p),0x80000000,1,None,3,0,None)
            self.assertNotIn(h,(None,ctypes.c_void_p(-1).value))
            def unlock():time.sleep(.08);k.CloseHandle(h)
            thread=threading.Thread(target=unlock);thread.start()
            try:self.assertTrue(atomic_json(p,{'version':2}))
            finally:thread.join()
            self.assertEqual(json.loads(p.read_text()),{'version':2})
            h=k.CreateFileW(str(p),0x80000000,1,None,3,0,None)
            try:
                self.assertFalse(atomic_json(p,{'version':3},attempts=2))
                self.assertEqual(json.loads(p.read_text()),{'version':2})
            finally:k.CloseHandle(h)
            self.assertTrue(atomic_json(p,{'version':3}))
            self.assertEqual(json.loads(p.read_text()),{'version':3})

    def test_restart_keeps_completed_receipt_without_raw_input(self):
        with tempfile.TemporaryDirectory() as folder:
            job=Path(folder);req=dict(id='1_2_3',model=4,world=5,epoch=6,mc_pid=7,generation=8)
            self.assertIsNone(completed_result(job,req))
            value=dict(req,ok=True,empty=True);atomic_json(job/'result.json',value)
            self.assertEqual(completed_result(job,req),value)
            self.assertIsNone(completed_result(job,dict(req,epoch=9)))
            (job/'result.json').write_text('')
            self.assertIsNone(completed_result(job,req))

    def test_new_blocks_bypass_old_entity_backlog(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);metadata={};done=set()
            for i in (1,2,10):
                job=root/f'1_2_{i}';job.mkdir();atomic_json(job/'request.json',dict(priority=1))
            self.assertEqual([p.parent.name for p in queued_requests(root,1,done,metadata)],['1_2_1','1_2_2','1_2_10'])
            job=root/'1_2_11';job.mkdir();atomic_json(job/'request.json',dict(priority=0))
            self.assertEqual(queued_requests(root,1,done,metadata)[0].parent.name,'1_2_11')
            done.add('1_2_11')
            self.assertEqual(len(queued_requests(root,1,done,metadata)),3)


if __name__=='__main__':unittest.main()
