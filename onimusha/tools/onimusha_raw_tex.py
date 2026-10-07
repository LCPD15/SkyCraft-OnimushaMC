"""Onimusha-specific TEX 251111100 storage, verified against supplied working TEX.

This title reuses MHS3's version number, but stores raw, row-padded BC blocks.
There is NO 8-byte-per-mip compressed-image table and NO GDeflate stream.
This module intentionally uses struct rather than the plugin's version heuristic.
"""
import struct
from pathlib import Path

VERSION=251111100
HEADER_SIZE=40
ROW_ALIGNMENT=256

def block_bytes(fmt):
    if fmt in (71,72,80,81):return 8
    if fmt in (74,75,77,78,83,84,95,96,98,99):return 16
    raise ValueError('Unsupported block compression format '+str(fmt))

def read_dds(path):
    data=Path(path).read_bytes()
    assert data[:4]==b'DDS ' and struct.unpack_from('<I',data,4)[0]==124
    assert data[84:88]==b'DX10', 'Only explicit DX10 DDS headers are supported'
    height,width=struct.unpack_from('<II',data,12)
    mip_count=struct.unpack_from('<I',data,28)[0]
    fmt,dimension,misc,array_size,_=struct.unpack_from('<5I',data,128)
    assert dimension==3 and array_size==1 and not(misc&4)
    offset=148;mips=[];bytes_per_block=block_bytes(fmt)
    for level in range(mip_count):
        w=max(1,width>>level);h=max(1,height>>level)
        row_bytes=((w+3)//4)*bytes_per_block;rows=(h+3)//4
        size=row_bytes*rows
        payload=data[offset:offset+size]
        assert len(payload)==size
        mips.append(payload);offset+=size
    assert offset==len(data), 'Unexpected DDS payload length'
    return dict(width=width,height=height,format=fmt,mip_count=mip_count,mips=mips)

def read_raw_tex(path):
    data=Path(path).read_bytes()
    assert data[:4]==b'TEX\0'
    version=struct.unpack_from('<I',data,4)[0]
    width,height,depth=struct.unpack_from('<HHH',data,8)
    images,mip_header_bytes=struct.unpack_from('<BB',data,14)
    fmt=struct.unpack_from('<I',data,16)[0]
    assert version==VERSION and images==1 and depth==1 and mip_header_bytes%16==0
    mip_count=mip_header_bytes//16;bytes_per_block=block_bytes(fmt)
    cursor=HEADER_SIZE+16*mip_count;mips=[];entries=[];padding_zero=True
    for level in range(mip_count):
        offset,pitch,size=struct.unpack_from('<QII',data,HEADER_SIZE+16*level)
        w=max(1,width>>level);h=max(1,height>>level)
        row_bytes=((w+3)//4)*bytes_per_block;rows=(h+3)//4
        assert offset==cursor, f'Mip {level}: data offset {offset}, expected {cursor}'
        assert pitch==((row_bytes+ROW_ALIGNMENT-1)//ROW_ALIGNMENT)*ROW_ALIGNMENT
        assert size==pitch*rows and offset+size<=len(data), f'Mip {level}: raw data range is outside file'
        unpacked=[]
        for row in range(rows):
            start=offset+row*pitch
            unpacked.append(data[start:start+row_bytes])
            padding_zero &= not any(data[start+row_bytes:start+pitch])
        mips.append(b''.join(unpacked))
        entries.append(dict(level=level,width=w,height=h,offset=offset,pitch=pitch,size=size))
        cursor=offset+size
    assert cursor==len(data), 'Extra table/trailing data found in raw TEX'
    return dict(width=width,height=height,format=fmt,mip_count=mip_count,mips=mips,
                header=data[:40],entries=entries,padding_zero=bool(padding_zero),version=version)

def encode_raw_tex(texture,header_template):
    header=bytearray(header_template)
    assert len(header)==40 and header[:4]==b'TEX\0'
    assert struct.unpack_from('<I',header,4)[0]==VERSION
    width,height,fmt=texture['width'],texture['height'],texture['format']
    count=texture['mip_count'];assert count==len(texture['mips']) and count<=15
    struct.pack_into('<HHHBBI',header,8,width,height,1,1,count*16,fmt)
    cursor=40+16*count;table=bytearray();body=bytearray()
    bytes_per_block=block_bytes(fmt)
    for level,payload in enumerate(texture['mips']):
        w=max(1,width>>level);h=max(1,height>>level)
        row_bytes=((w+3)//4)*bytes_per_block;rows=(h+3)//4
        pitch=((row_bytes+255)//256)*256;size=pitch*rows
        assert len(payload)==row_bytes*rows
        table.extend(struct.pack('<QII',cursor,pitch,size))
        padding=bytes(pitch-row_bytes)
        for row in range(rows):body.extend(payload[row*row_bytes:(row+1)*row_bytes]+padding)
        cursor+=size
    return bytes(header+table+body)

def write_from_dds(dds_path,out_path,reference_tex):
    reference=read_raw_tex(reference_tex)
    source=read_dds(dds_path)
    Path(out_path).parent.mkdir(parents=True,exist_ok=True)
    Path(out_path).write_bytes(encode_raw_tex(source,reference['header']))
    verified=read_raw_tex(out_path)
    assert verified['mips']==source['mips'], 'BC block payload differs from original DDS'
    return verified
