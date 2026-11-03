#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..'),{Dex}=require(path.join(root,'BattleEngine/node_modules/pokemon-showdown'));
const read=p=>JSON.parse(fs.readFileSync(path.join(root,p),'utf8'));
const catalog=read('BattleEngine/challenge-opponents.json'),text=read('Sources/PokeTokenBar/Resources/BattleText/catalog.json'),names=read('Sources/PokeTokenBar/Resources/BattleText/ChallengeTrainers/names.json');
const references=read('scripts/challenge/item-reference.json').members;
const itemNames=Object.fromEntries(read('BattleEngine/held-items.json').items.map(i=>[i.id,i.names.ko]));
Object.assign(itemNames,{eviolite:'진화의휘석',oranberry:'오랭열매',custapberry:'애슈열매',chestoberry:'유루열매',liechiberry:'치리열매',whiteherb:'하양허브',heatrock:'뜨거운바위',damprock:'축축한바위',lightclay:'빛의점토',lightball:'전기구슬',blacksludge:'검은진흙',choiceband:'구애머리띠',choicespecs:'구애안경',choicescarf:'구애스카프',flameorb:'화염구슬',flyinggem:'비행주얼',fightinggem:'격투주얼',airballoon:'풍선',yacheberry:'플카열매',chopleberry:'로플열매',shedshell:'아름다운허물'});
const itemName=id=>itemNames[id]||Dex.mod('gen5').items.get(id).name;
const changed=catalog.encounters.flatMap(e=>e.team).filter(p=>p.item!==references[p.id].previousItem).length;
const itemLines=['# 챌린지 27팀 도구 배정 검토','','기술·특성·역할을 기준으로 작성한 후보 점수의 합이 가장 높도록 팀 6마리의 도구를 함께 배정합니다. 후보 점수는 수동 설계한 기준이며 실전 승률의 수학적 최적값이나 머신러닝 결과를 의미하지 않습니다. 앱에서는 계산하거나 랜덤으로 고르지 않고 검토가 끝난 고정 명단만 사용합니다.','',`전체 162마리 중 기존 배정 대비 ${changed}마리 변경. 같은 팀의 도구는 중복하지 않습니다. 레드의 뮤츠 생명의구슬·리자몽 리자몽나이트Y·이상해꽃 검은진흙은 고정합니다.`,'','추천 도구 출처: https://pkmn.github.io/smogon/data/sets/gen5.json','5세대 효과 검증: 프로젝트에 고정된 Pokémon Showdown 0.11.11 Gen5 데이터. 후보·배정 근거는 scripts/challenge/optimize-items.cjs 및 item-reference.json에 보관합니다.',''];
const key=s=>s.toLowerCase().replace(/[^a-z0-9]/g,'');
const lines=['# 27연전 고정 상대 포켓몬·기술배치','','현재 프로젝트의 고정 상대 데이터 기준이며 체육관 관장과 사천왕(1~24전)은 레벨 95, 그린·목호(2세대)·레드(25~27전)는 레벨 100입니다. 표는 등록 순서이고, 실제 선발은 학습된 CPU가 선택하므로 첫 등장 포켓몬은 달라질 수 있습니다.','','잠재파워의 타입은 실제 개체값과 5세대 엔진으로 계산했습니다. 레드의 포켓몬은 개체값 31(별 32)이며, 리자몽은 리자몽나이트Y로 메가진화합니다.',''];
for(const e of catalog.encounters){
 const trainerKey=e.id==='ltsurge'?'lt_surge':e.id.replace(/[12]$/,'');let name=names[trainerKey].ko;
 if(['koga2','bruno2','lance2'].includes(e.id))name+=' (2세대)';
 const role=e.id==='red'?'포켓몬 마스터':['blue','lance2'].includes(e.id)?'챔피언':e.index>=16&&e.index<24?'사천왕':'체육관 관장';
 lines.push(`## ${e.index+1}전 · ${role} ${name} · Lv.${e.team[0].level}`,'','| 순서 | 포켓몬 | 특성 | 기술배치 | 도구 |','|---|---|---|---|---|');
 itemLines.push(`## ${e.index+1}전 · ${role} ${name}`,'','| 포켓몬 | 기존 도구 | 적용 도구 | 배정 이유 |','|---|---|---|---|');
 e.team.forEach((p,i)=>{
  let mon=text.species[p.speciesID].ko,ability=text.abilities[key(p.ability)]?.ko||p.ability;
  if(e.id==='red'&&p.speciesID===6){mon+=' → 메가리자몽Y';ability+=' → 가뭄';}
  const moves=p.moves.map(m=>{const id=key(m),move=text.moves[id.startsWith('hiddenpower')?'hiddenpower':id];if(!move)throw Error(`Missing move: ${m}`);let result=move.names.ko;
   if(id.startsWith('hiddenpower'))result+=` (${text.types[Dex.mod('gen5').getHiddenPower(p.ivs).type.toLowerCase()].ko})`;
   return result;
  });
  lines.push(`| ${i+1} | ${mon} | ${ability} | ${moves.join(' / ')} | ${itemName(p.item)} |`);
  let reason=p.evidence.itemOptimization.reason;
  for(const [type,names]of Object.entries(text.types))reason=reason.replace(` ${type[0].toUpperCase()+type.slice(1)} 타입`,` ${names.ko} 타입`);
  itemLines.push(`| ${mon} | ${itemName(references[p.id].previousItem)} | ${itemName(p.item)} | ${reason} |`);
 });lines.push('');itemLines.push('');
}
const sha=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'BattleEngine/challenge-opponents.json'))).digest('hex');
lines.push(`원본: \`BattleEngine/challenge-opponents.json\` · SHA-256: \`${sha}\``,'');
const out=path.join(root,'docs/reference/challenge/opponent-rosters.ko.md');fs.writeFileSync(out,lines.join('\n'));console.log(out);
itemLines.push(`원본: \`BattleEngine/challenge-opponents.json\` · SHA-256: \`${sha}\``,'');
const itemOut=path.join(root,'docs/reference/challenge/opponent-items.ko.md');fs.writeFileSync(itemOut,itemLines.join('\n'));console.log(itemOut);
