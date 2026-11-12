import assert from 'node:assert/strict';
export const MARKER=[5,2,7,1,6,3,0,4,3,6,1,7,2,5,4,0];
export const COLUMNS=64, ROWS=24, CELL=2, PAGE_SIZE=512, MAX_PACKET=180000;
export function adler32(bytes){let a=1,b=0;for(const value of bytes){a=(a+value)%65521;b=(b+a)%65521;}return(b*65536+a)>>>0;}
export function encodePage(packet,requestId,page){
 const bytes=Buffer.from(packet),count=Math.ceil(bytes.length/PAGE_SIZE);assert(bytes.length>0&&bytes.length<=MAX_PACKET&&page>=0&&page<count);
 const part=bytes.subarray(page*PAGE_SIZE,(page+1)*PAGE_SIZE),head=Buffer.alloc(32);head.write('NIBPIX2!');head.writeUInt32BE(adler32(Buffer.from(requestId)),8);head.writeUInt16BE(page,12);head.writeUInt16BE(count,14);head.writeUInt16BE(part.length,16);head.writeUInt32BE(bytes.length,18);head.writeUInt32BE(adler32(bytes),22);head.writeUInt32BE(adler32(part),26);return Buffer.concat([head,part]);
}
export function parsePage(bytes){
 if(!Buffer.isBuffer(bytes))bytes=Buffer.from(bytes);
 if(bytes.length<32||bytes.subarray(0,8).toString()!=='NIBPIX2!')throw Error('Invalid optical marker');
 const nonce=bytes.readUInt32BE(8),index=bytes.readUInt16BE(12),count=bytes.readUInt16BE(14),length=bytes.readUInt16BE(16),total=bytes.readUInt32BE(18),checksum=bytes.readUInt32BE(22),partChecksum=bytes.readUInt32BE(26);
 if(total<1||total>MAX_PACKET||count!==Math.ceil(total/PAGE_SIZE)||index>=count||length!==Math.min(PAGE_SIZE,total-index*PAGE_SIZE)||bytes.length<32+length)throw Error('Invalid optical frame bounds');
 const body=bytes.subarray(32,32+length);if(adler32(body)!==partChecksum)throw Error('Optical page checksum mismatch');return{nonce,index,count,total,checksum,body};
}
export class PageAssembler{
 constructor(){this.reset();}
 reset(){this.key=null;this.parts=new Map();this.started=0;}
 accept(bytes,now=Date.now()){
  const page=parsePage(bytes),key=[page.nonce,page.count,page.total,page.checksum].join(':');
  if(this.key!==key||now-this.started>180000){this.reset();this.key=key;this.started=now;}
  this.parts.set(page.index,page.body);if(this.parts.size!==page.count)return null;
  const packet=Buffer.concat(Array.from({length:page.count},(_,i)=>this.parts.get(i)));
  if(packet.length!==page.total||adler32(packet)!==page.checksum){this.reset();throw Error('Optical request checksum mismatch');}
  return{packet:packet.toString('ascii'),nonce:page.nonce};
 }
}
