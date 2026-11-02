#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..'),{Dex}=require(path.join(root,'BattleEngine/node_modules/pokemon-showdown'));
const read=p=>JSON.parse(fs.readFileSync(path.join(root,p),'utf8'));
const catalog=read('BattleEngine/challenge-opponents.json'),text=read('Sources/PokeTokenBar/Resources/BattleText/catalog.json'),names=read('Sources/PokeTokenBar/Resources/BattleText/ChallengeTrainers/names.json');
const key=s=>s.toLowerCase().replace(/[^a-z0-9]/g,'');
const lines=['# 27연전 고정 상대 포켓몬·기술배치','','현재 프로젝트의 고정 상대 데이터 기준이며 1~12전은 레벨 75, 13~16전은 레벨 90, 사천왕이 시작되는 17전부터는 레벨 100입니다. 표는 등록 순서이고, 실제 선발은 학습된 CPU가 선택하므로 첫 등장 포켓몬은 달라질 수 있습니다.','','잠재파워의 타입은 실제 개체값과 5세대 엔진으로 계산했습니다. 레드의 포켓몬은 개체값 31(별 32)이며, 리자몽은 리자몽나이트Y로 메가진화합니다.',''];
for(const e of catalog.encounters){
 const trainerKey=e.id==='ltsurge'?'lt_surge':e.id.replace(/[12]$/,'');let name=names[trainerKey].ko;
 if(['koga2','bruno2','lance2'].includes(e.id))name+=' (2세대)';
 const role=e.id==='red'?'포켓몬 마스터':['blue','lance2'].includes(e.id)?'챔피언':e.index>=16&&e.index<24?'사천왕':'체육관 관장';
 lines.push(`## ${e.index+1}전 · ${role} ${name} · Lv.${e.team[0].level}`,'','| 순서 | 포켓몬 | 특성 | 기술배치 |','|---|---|---|---|');
 e.team.forEach((p,i)=>{
  let mon=text.species[p.speciesID].ko,ability=text.abilities[key(p.ability)]?.ko||p.ability;
  if(e.id==='red'&&p.speciesID===6){mon+=' → 메가리자몽Y';ability+=' → 가뭄';}
  const moves=p.moves.map(m=>{const id=key(m),move=text.moves[id.startsWith('hiddenpower')?'hiddenpower':id];if(!move)throw Error(`Missing move: ${m}`);let result=move.names.ko;
   if(id.startsWith('hiddenpower'))result+=` (${text.types[Dex.mod('gen5').getHiddenPower(p.ivs).type.toLowerCase()].ko})`;
   return result;
  });
  lines.push(`| ${i+1} | ${mon} | ${ability} | ${moves.join(' / ')} |`);
 });lines.push('');
}
const sha=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'BattleEngine/challenge-opponents.json'))).digest('hex');
lines.push(`원본: \`BattleEngine/challenge-opponents.json\` · SHA-256: \`${sha}\``,'');
const out=path.join(root,'docs/reference/challenge/opponent-rosters.ko.md');fs.writeFileSync(out,lines.join('\n'));console.log(out);
