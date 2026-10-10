"""Windows-safe mailbox publication while REFramework may have JSON files open."""
import json
import os
import time
import re


def atomic_json(path, data, attempts=8):
    # Readers see either the previous JSON or the complete new document.
    tmp=path.with_suffix('.tmp')
    tmp.write_text(json.dumps(data,ensure_ascii=False),encoding='utf-8')
    for attempt in range(attempts):
        try:
            os.replace(tmp,path)
            return True
        except OSError as exc:
            if not isinstance(exc,PermissionError) and getattr(exc,'winerror',None) not in (5,32,33):raise
            if attempt+1<attempts:time.sleep(min(.01*2**attempt,.1))
    # A heartbeat can wait. Results must remain queued until publication succeeds.
    return False


def completed_result(job, request):
    """Never replace a completed receipt after its raw input has been removed."""
    try:value=json.loads((job/'result.json').read_text(encoding='utf-8'))
    except (OSError,ValueError):return None
    fields=('id','model','world','epoch','mc_pid','generation')
    if not isinstance(value,dict) or any(value.get(k)!=request.get(k) for k in fields):return None
    if bool(value.get('white_flash'))!=bool(request.get('white_flash')):return None
    if type(value.get('ok')) is not bool:return None
    if value['ok'] and not (value.get('empty') or (value.get('asset_id') and value.get('files'))):return None
    return value


def queued_requests(root,host_pid,done,metadata):
    rows=[]
    for path in root.glob(str(host_pid)+'_*_*/request.json'):
        if path.parent.name in done:continue
        try:
            order=tuple(map(int,path.parent.name.split('_')))
            if path not in metadata:metadata[path]=json.loads(path.read_text(encoding='utf-8'))
            priority=0 if metadata[path].get('priority')==0 else 1
            rows.append((priority,order,path))
        except (ValueError,OSError):continue
    rows.sort(key=lambda row:(row[0],row[1]))
    return [row[2] for row in rows]


class RequestInbox:
    """One legacy recovery scan at startup, then only unfinished atomic tickets.

    The result folders are immutable receipt archives, not a work queue. Walking
    them every 50 ms made idle conversion cost grow with the whole play session.
    """
    def __init__(self, root, host_pid):
        self.root=root;self.host_pid=host_pid;self.inbox=root/'inbox'
        self.inbox.mkdir(exist_ok=True)
        self.legacy={};self.metadata={};self.completed=0
        for path in root.glob(str(host_pid)+'_*_*/request.json'):
            try:
                request=json.loads(path.read_text(encoding='utf-8'))
                result=completed_result(path.parent,request)
                if result is not None and (not result['ok'] or result.get('empty') or result.get('loader_version')==1):
                    self.completed+=1
                    (self.inbox/(path.parent.name+'.json')).unlink(missing_ok=True)
                else:self.legacy[path.parent.name]=path
            except (OSError,ValueError):continue

    def queued(self):
        paths=dict(self.legacy)
        for ticket in self.inbox.glob(str(self.host_pid)+'_*_*.json'):
            if re.fullmatch(r'\d+_\d+_\d+',ticket.stem):paths[ticket.stem]=self.root/ticket.stem/'request.json'
        rows=[]
        for name,path in paths.items():
            try:
                if name not in self.metadata:self.metadata[name]=json.loads(path.read_text(encoding='utf-8'))
                priority=0 if self.metadata[name].get('priority')==0 else 1
                rows.append((priority,tuple(map(int,name.split('_'))),path))
            except (OSError,ValueError):continue
        rows.sort(key=lambda row:(row[0],row[1]))
        return [row[2] for row in rows]

    def finish(self, job):
        # Safe after the result publication fence; restart reconstructs from the
        # receipt even if Windows temporarily prevents removing the ticket.
        (self.inbox/(job.name+'.json')).unlink(missing_ok=True)
        self.metadata.pop(job.name,None);self.legacy.pop(job.name,None)
        self.completed+=1
