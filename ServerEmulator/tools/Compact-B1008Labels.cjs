'use strict';
// Exact, reversible generation for a separately prepared client.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const options=new Map();
for(let i=3;i<process.argv.length;i+=2){
 assert(['--source','--client','--backups'].includes(process.argv[i]),'Unknown path option');
 assert(process.argv[i+1]&&!options.has(process.argv[i]),'Missing/duplicate path option');
 options.set(process.argv[i],path.resolve(process.argv[i+1]));
}
assert(options.has('--source')&&options.has('--client')&&options.has('--backups'),'Use --source <original> --client <prepared> --backups <separate directory>');
const sourceRoot=options.get('--source'),clientRoot=options.get('--client'),backupRoot=options.get('--backups');
const within=(a,b)=>a.toLowerCase()===b.toLowerCase()||a.toLowerCase().startsWith(b.toLowerCase()+path.sep);
assert(!within(sourceRoot,clientRoot)&&!within(clientRoot,sourceRoot),'Source and client must be disjoint');
assert(!within(backupRoot,sourceRoot)&&!within(backupRoot,clientRoot),'Backups must be outside source and client');
const relative='resource/Interface/IE_Lod/string.lod_eng';
const source=path.join(sourceRoot,relative);
const target=path.join(clientRoot,relative);
const manifestPath=path.join(clientRoot,'LOCAL-CLIENT-MANIFEST.json');
const originalHash='99acbce9c5bff5e16be2a1e53cde53057a6c22aff0b71ca181b3eb24882676ba';
const previousTooltipHash='104138f3ddf4b63e76e512319ad1d6ff19b1fef1cccbec783cc773fa31069464';
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const labels=[
 [21133,'HP Regeneration','HP Regen'],[21134,'MP Regeneration','MP Regen'],
 [21135,'Physical Attack (min)','P.Atk Min'],[21137,'Physical Attack (max)','P.Atk Max'],
 [21138,'Physical Defense','P.Def'],[21136,'Magical Attack (min)','M.Atk Min'],
 [21139,'Magical Attack (max)','M.Atk Max'],[21140,'Magical Defense','M.Def'],
 [21141,'Evasion Rate','Evasion'],[21142,'Block Rate','Block'],[21143,'Critical Chance','Crit Chance'],
 // Untranslated CP949 labels in the English CBT resource. The Latin font
 // renders these as mojibake. Keep skill values and descriptions untouched.
 [31363,{hex:'c5b8bcf6'},'Hits'],
 [31364,{hex:'c3dfb0a1b9b0b8aeb0f8b0ddb7c2'},'Bonus P.Atk'],
 [31365,{hex:'c3dfb0a1b8b6b9fdb0f8b0ddb7c2'},'Bonus M.Atk'],
 [31366,{hex:'c1f6bcd3bdc3b0a3'},'Duration'],
 [31367,{hex:'c1d6b1e2'},'Interval'],
 [31368,{hex:'c0e5baf1b9b0b8aeb0f8b0ddb7c2'},'Gear P.Atk'],
 [31369,{hex:'c0e5baf1b8b6b9fdb0f8b0ddb7c2'},'Gear M.Atk'],
 [31370,{hex:'c5a9b8aec6bcc4c3b9e8bcf6'},'Crit Mult.'],
 [31371,{hex:'b0f8b0ddbcd3b5b5'},'Atk Speed'],
 [31372,{hex:'b8b6b9fdc4b3bdbac6c3bcd3b5b5'},'Cast Speed'],
 [31373,{hex:'b8b6b9fdbdc3c0fcb0c5b8ae'},'Cast Range'],
 [31374,{hex:'c0e5baf1b9b0b8aeb9e6beeeb7c2'},'Gear P.Def'],
 [31375,{hex:'c0e5baf1b8b6b9fdb9e6beeeb7c2'},'Gear M.Def'],
 [31376,{hex:'b5a5b9ccc1f6c8edbcf6'},'Absorb'],
 [31377,{hex:'c0babdc5'},'Stealth'],
 [31378,{hex:'beeeb1d7b7ce'},'Aggro'],
 [31379,{hex:'c0ccb5bfbcd3b5b5'},'Move Speed'],
 [31380,{hex:'4850c8b8bab9b7fc'},'HP Regen'],
 [31381,{hex:'4d50c8b8bab9b7fc'},'MP Regen'],
 [31382,{hex:'4850c8edbcf6'},'HP Drain'],
 [31383,{hex:'4d50c8edbcf6'},'MP Drain'],
 [31384,{hex:'bbf3c5c2c0ccbbf3'},'Status'],
 [31385,{hex:'b0f8c6f7'},'Fear'],
 [31386,{hex:'bdbac5b3c1beb7f9'},'Type'],
 // 0x509D36 and 0x50AD6F print current SKILL rank + 1 here, not
 // skillLevel.requiredLevel. The original Korean label is misleading too.
 [31387,{hex:'c7cabfe4b7b9baa7'},'Skill Rank'],
 [31388,{hex:'b3b2c0babdc3b0a3'},'Time Left']
];
const mode=process.argv[2];assert(['--apply','--verify'].includes(mode),'Use --apply or --verify');
for(const p of [source,target,manifestPath]){
 assert.equal(fs.realpathSync(p).toLowerCase(),path.resolve(p).toLowerCase(),'Refusing redirected path');
 assert.equal(fs.lstatSync(p).nlink,1,'Refusing hard-linked client file');
}
const original=fs.readFileSync(source);assert.equal(hash(original),originalHash,'Archived source changed');
const generated=Buffer.from(original),count=original.readUInt32LE();
let legacyGenerated;
assert.equal(original.length,4+count*1028,'Unexpected string table layout');
const changedBytes=new Set();
for(const [id,expected,replacement] of labels){
 const offsets=[];for(let i=0;i<count;i++){const p=4+i*1028;if(original.readUInt32LE(p)===id)offsets.push(p+4);}
 assert.equal(offsets.length,1,'Missing/duplicate label '+id);const p=offsets[0];
 const end=original.indexOf(0,p);assert(end>=p&&end<p+1024);
 const expectedBytes=typeof expected==='string'?Buffer.from(expected,'ascii'):Buffer.from(expected.hex,'hex');
 assert(original.subarray(p,end).equals(expectedBytes),'Unexpected source label '+id);
 assert(replacement.length<1024&&/^[\x20-\x7e]+$/.test(replacement));
 const patchEnd=Math.max(end,p+replacement.length);
 for(let j=end;j<=patchEnd;j++)assert.equal(original[j],0,'Nonzero string padding');
 generated.fill(0,p,patchEnd+1);generated.write(replacement,p,'ascii');
 for(let j=p;j<=patchEnd;j++)changedBytes.add(j);
 if(id===21143)legacyGenerated=Buffer.from(generated);
}
for(let i=0;i<original.length;i++)if(!changedBytes.has(i))assert.equal(generated[i],original[i]);
const current=fs.readFileSync(target),generatedHash=hash(generated);
const manifestBytes=fs.readFileSync(manifestPath),manifest=JSON.parse(manifestBytes);
const records=manifest.Files.filter(r=>r.Path.replaceAll('\\','/')===relative);assert.equal(records.length,1);
if(mode==='--verify'){
 assert(current.equals(generated),'Resource differs from the exact compact-label patch');
 assert.equal(records[0].SHA256,generatedHash,'Resource manifest mismatch');
}else{
 assert(current.equals(original)||current.equals(legacyGenerated)||current.equals(generated)||hash(current)===previousTooltipHash,'Unknown local resource edits; refusing overwrite');
 assert.equal(records[0].SHA256,hash(current),'Unexpected manifest hash');
 fs.mkdirSync(backupRoot,{recursive:true});
 assert.equal(fs.realpathSync(backupRoot).toLowerCase(),backupRoot.toLowerCase());
 const backup=fs.mkdtempSync(path.join(backupRoot,'compact-labels-'));
 fs.writeFileSync(path.join(backup,'string.lod_eng'),current,{flag:'wx'});
 fs.writeFileSync(path.join(backup,'LOCAL-CLIENT-MANIFEST.json'),manifestBytes,{flag:'wx'});
 records[0].SHA256=generatedHash;
 if(!manifest.Changed.some(p=>p.replaceAll('\\','/')===relative))manifest.Changed.push(relative.replaceAll('/','\\'));
 manifest.CompactLabels={version:3,sourceSHA256:originalHash,generatedSHA256:generatedHash,labelIDs:labels.map(r=>r[0])};
 fs.writeFileSync(target,generated);
 fs.writeFileSync(manifestPath,JSON.stringify(manifest,null,2)+'\n');
 assert(fs.readFileSync(target).equals(generated));
 console.log('Backup: '+backup);
}
assert.equal(hash(fs.readFileSync(source)),originalHash,'Archived source was modified');
console.log('PASS: '+labels.length+' compact labels; all other resource bytes unchanged; SHA256 '+generatedHash);
