import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const W=48,H=64,S=4;
const palette={ink:[17,39,42,255],shade:[30,100,99,255],body:[63,174,145,255],light:[135,224,171,255],cream:[255,236,184,255],white:[255,252,223,255],orange:[237,139,74,255],gold:[251,192,91,255],brown:[117,72,48,255],blue:[78,164,191,255]};
function draw(blink){
 const pixels=Array.from({length:W*H},()=>[0,0,0,0]);
 const dot=(x,y,c)=>{if(x>=0&&x<W&&y>=0&&y<H)pixels[y*W+x]=palette[c];};
 const rect=(x,y,w,h,c)=>{for(let yy=y;yy<y+h;yy++)for(let xx=x;xx<x+w;xx++)dot(xx,yy,c);};
 const oval=(x,y,rx,ry,c)=>{for(let yy=Math.floor(y-ry);yy<=y+ry;yy++)for(let xx=Math.floor(x-rx);xx<=x+rx;xx++)if(((xx-x)/rx)**2+((yy-y)/ry)**2<=1)dot(xx,yy,c);};
 // Original little amphibious cartographer: dorsal frill, satchel, enormous eyes.
 rect(22,3,4,9,'ink');rect(23,4,2,7,'orange');rect(16,7,4,7,'ink');rect(17,8,2,5,'gold');rect(29,7,4,8,'ink');rect(30,8,2,6,'orange');
 oval(24,42,13,17,'ink');oval(24,42,11,15,'shade');oval(23,40,10,14,'body');oval(23,44,7,10,'light');
 oval(15,58,8,3,'ink');oval(33,58,8,3,'ink');rect(10,56,11,3,'body');rect(29,56,10,3,'body');rect(8,59,13,1,'light');rect(29,59,13,1,'light');
 oval(24,24,18,16,'ink');oval(24,24,16,14,'body');oval(24,29,13,7,'light');
 oval(14,18,9,11,'ink');oval(34,18,9,11,'ink');oval(14,18,7,9,'white');oval(34,18,7,9,'white');
 if(blink){rect(9,18,11,2,'ink');rect(29,18,11,2,'ink');}else{oval(16,19,3,5,'ink');oval(32,19,3,5,'ink');rect(16,16,2,2,'white');rect(31,16,2,2,'white');}
 rect(20,27,9,2,'ink');rect(18,29,13,4,'ink');rect(20,32,9,2,'ink');rect(20,29,2,2,'white');rect(27,29,2,2,'white');rect(23,32,4,1,'orange');
 rect(9,28,4,2,'orange');rect(36,28,3,2,'orange');
 // Diagonal satchel strap and goofy little folded map.
 for(let i=0;i<15;i++){dot(15+i,35+i,'brown');dot(16+i,35+i,'gold');}
 oval(11,42,4,7,'ink');oval(11,42,2,5,'body');
 rect(32,39,11,14,'ink');rect(33,40,9,12,'cream');rect(36,40,1,12,'gold');rect(39,40,1,12,'gold');rect(34,43,5,1,'blue');rect(37,44,3,1,'blue');rect(36,45,2,1,'blue');rect(34,48,2,2,'orange');
 oval(33,46,3,3,'ink');oval(33,46,2,2,'body');
 return pixels;
}
function rgba(pixels){const b=Buffer.alloc(W*S*H*S*4);for(let y=0;y<H*S;y++)for(let x=0;x<W*S;x++)Buffer.from(pixels[Math.floor(y/S)*W+Math.floor(x/S)]).copy(b,(y*W*S+x)*4);return b;}
function tga(bytes){const width=256,header=Buffer.alloc(18);header[2]=2;header.writeUInt16LE(width,12);header.writeUInt16LE(H*S,14);header[16]=32;header[17]=0x28;const out=Buffer.alloc(width*H*S*4);for(let y=0;y<H*S;y++)for(let x=0;x<W*S;x++){const i=(y*W*S+x)*4,k=(y*width+x+32)*4;out[k]=bytes[i+2];out[k+1]=bytes[i+1];out[k+2]=bytes[i];out[k+3]=bytes[i+3];}return Buffer.concat([header,out]);}
function crc(bytes){let c=0xffffffff;for(const b of bytes){c^=b;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0);}return(c^0xffffffff)>>>0;}
function chunk(name,data){const n=Buffer.from(name),l=Buffer.alloc(4),s=Buffer.alloc(4);l.writeUInt32BE(data.length);s.writeUInt32BE(crc(Buffer.concat([n,data])));return Buffer.concat([l,n,data,s]);}
function png(bytes){const hdr=Buffer.alloc(13);hdr.writeUInt32BE(W*S,0);hdr.writeUInt32BE(H*S,4);hdr[8]=8;hdr[9]=6;const rows=[];for(let y=0;y<H*S;y++)rows.push(Buffer.from([0]),bytes.subarray(y*W*S*4,(y+1)*W*S*4));return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',hdr),chunk('IDAT',zlib.deflateSync(Buffer.concat(rows))),chunk('IEND',Buffer.alloc(0))]);}
const art=path.join(root,'addon','NibWhisper','Textures'),pub=path.join(root,'companion','public');fs.mkdirSync(art,{recursive:true});fs.mkdirSync(pub,{recursive:true});
for(const [name,blink] of [['Nib',false],['NibBlink',true]]){const bytes=rgba(draw(blink));fs.writeFileSync(path.join(art,name+'.tga'),tga(bytes));if(!blink)fs.writeFileSync(path.join(pub,'nib.png'),png(bytes));}
console.log('Built original Nib sprite and blink textures.');
