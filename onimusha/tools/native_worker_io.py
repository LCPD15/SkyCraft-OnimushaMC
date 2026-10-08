"""Windows-safe mailbox publication while REFramework may have JSON files open."""
import json
import os
import time


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
