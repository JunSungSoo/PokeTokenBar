'use strict';
// Offline, authored role preferences. No random choices or runtime equipment search.
const reference=require('./item-reference.json');
const VERSION='bw-role-items-v1';
const RED_LOCKS={'red-150':'lifeorb','red-6':'charizarditey','red-3':'blacksludge'};
const typeItems={Normal:'silkscarf',Fire:'charcoal',Water:'mysticwater',Electric:'magnet',Grass:'miracleseed',Ice:'nevermeltice',Fighting:'blackbelt',Poison:'poisonbarb',Ground:'softsand',Flying:'sharpbeak',Psychic:'twistedspoon',Bug:'silverpowder',Rock:'hardstone',Ghost:'spelltag',Dragon:'dragonfang',Dark:'blackglasses',Steel:'metalcoat'};
function traits(p,dex){
 const species=dex.species.get(p.species),moves=p.moves.map(raw=>{
  const move=dex.moves.get(raw);
  return move.id.startsWith('hiddenpower')?{...move,type:dex.getHiddenPower(p.ivs).type}:move;
 });
 const attack=moves.filter(m=>m.category!=='Status'&&!m.damage&&!m.damageCallback);
 const physical=attack.filter(m=>m.category==='Physical'&&m.id!=='foulplay');
 const special=attack.filter(m=>m.category==='Special');
 const status=moves.filter(m=>m.category==='Status'),has=id=>moves.some(m=>m.id===id);
 const recovery=moves.some(m=>['recover','roost','softboiled','slackoff','milkdrink','moonlight','morningsun','synthesis','rest','wish'].includes(m.id));
 const setup=moves.some(m=>['swordsdance','nastyplot','dragondance','quiverdance','shellsmash','calmmind','bulkup','curse','coil','rockpolish','growth'].includes(m.id));
 const role=reference.members[p.id]?.role || p.evidence?.set || '';
 const hazards=moves.some(m=>['stealthrock','spikes','toxicspikes'].includes(m.id));
 const disposable=has('memento')||(/suicide lead/i.test(role));
 const support=(/rapid spin/i.test(role)&&status.length>0)||(species.baseStats.spe<=65&&['curse','coil','bulkup'].some(has))||status.length>=2||/support|defensive|utility|resttalk|subseed|cleric|tank|hazard control|bulky/i.test(role);
 return {species,moves,attack,physical,special,status,has,recovery,setup,role,support,hazards,disposable,ability:dex.toID(p.ability)};
}
function suitability(p,item,dex){
 const t=traits(p,dex),id=dex.toID(item),i=dex.items.get(id);
 if(RED_LOCKS[p.id]===id)return null;
 if(!i.exists||i.gen>5)return 'not-bw';
 if(id==='eviolite'&&!t.species.nfe)return 'fully-evolved';
 if(id==='blacksludge'&&!t.species.types.includes('Poison'))return 'not-poison';
 if(id==='lightball'&&t.species.num!==25)return 'not-pikachu';
 if(id==='lightclay'&&!t.has('reflect')&&!t.has('lightscreen'))return 'no-screens';
 if(['heat rock','damp rock','smooth rock','icy rock'].map(dex.toID).includes(id)){
  const weather={heatrock:'sunnyday',damprock:'raindance',smoothrock:'sandstorm',icyrock:'hail'}[id];
  if(!t.has(weather))return 'no-weather-move';
 }
 if(id.startsWith('choice')){
  if(t.status.some(m=>!['trick','switcheroo','sleeptalk'].includes(m.id)))return 'locks-support-moves';
  if(id==='choiceband'&&!t.physical.length)return 'no-physical';
  if(id==='choicespecs'&&!t.special.length)return 'no-special';
 }
 if(id==='wiseglasses'&&!t.special.length)return 'no-special';
 if(id==='muscleband'&&!t.physical.length)return 'no-physical';
 if(['lifeorb','expertbelt'].includes(id)&&!t.attack.length)return 'no-boostable-attack';
 if(id==='focussash'&&t.ability==='sturdy')return 'sturdy-redundancy';
 if(id==='whiteherb'&&!t.has('shellsmash')&&!t.moves.some(m=>m.self?.boosts&&Object.values(m.self.boosts).some(n=>n<0)))return 'no-stat-drop';
 if(id==='flameorb'&&!['guts','quickfeet'].includes(t.ability))return 'no-status-benefit';
 if(id==='toxicorb'&&!['poisonheal','guts','quickfeet'].includes(t.ability))return 'no-status-benefit';
 if(id==='flameorb'&&t.species.types.includes('Fire'))return 'burn-immune';
 if(id==='toxicorb'&&t.species.types.some(s=>['Poison','Steel'].includes(s)))return 'poison-immune';
 if(id==='chestoberry'&&(!t.has('rest')||t.has('sleeptalk')))return 'no-rest-wake-role';
 if(id==='liechiberry'&&(!t.has('endure')||!t.has('reversal')))return 'no-endure-reversal';
 if(id==='custapberry'&&t.ability!=='sturdy'&&!t.has('endure'))return 'no-low-hp-activation-plan';
 if(id.endsWith('gem')){
  const type=id.slice(0,-3);
  if(!t.attack.some(m=>dex.toID(m.type)===type))return 'no-matching-attack';
 }
 for(const [type,boostItem]of Object.entries(typeItems))if(id===boostItem&&!t.attack.some(m=>m.type===type))return 'no-matching-attack';
 return null;
}
function itemCandidates(p,dex){
 if(RED_LOCKS[p.id])return [{item:RED_LOCKS[p.id],score:1000,reason:'사용자 지정 도구 유지'}];
 const t=traits(p,dex),map=new Map();
 const add=(item,score,reason)=>{
  const id=dex.toID(item);if(suitability(p,id,dex))return;
  const old=map.get(id);if(!old||old.score<score)map.set(id,{item:id,score,reason});
 };
 // Bulk and longevity compete for the same team resource, rather than first-slot wins.
 add('sitrusberry',t.support?85:65,'최대 HP 25% 회복으로 중복 없는 생존 보완');
 add('lumberry',t.setup?96:72,'상태이상 해제로 행동 및 강화 기회 확보');
 add('leftovers',t.disposable?45:t.has('substitute')||t.has('wish')?122:t.support?115:78,'회복·장기전 역할의 지속 회복');
 if(t.species.types.includes('Poison'))add('blacksludge',t.support||t.recovery?121:86,'독 타입의 지속 회복으로 공격 도구와 역할 분담');
 if(t.species.nfe)add('eviolite',110+(t.species.baseStats.def+t.species.baseStats.spd)/10+(t.support?12:0)+(t.attack.length===0?20:0),'미진화체의 방어·특수방어 1.5배 강화');
 if(t.species.num===25)add('lightball',250,'피카츄 전용 공격·특수공격 2배');
 if(t.support&&t.species.baseStats.def>=75)add('rockyhelmet',94+t.species.baseStats.def/30,'물리 접촉을 받아내는 방어·지원 역할');
 if(t.species.types.includes('Steel')&&t.support)add('shedshell',87,'자력 포획을 피해 지원 포켓몬의 교체 보장');
 if(t.has('reflect')||t.has('lightscreen'))add('lightclay',145,'리플렉터·빛의장막 지속 턴 연장');
 for(const [move,item]of Object.entries({sunnyday:'heatrock',raindance:'damprock',sandstorm:'smoothrock',hail:'icyrock'})){
  if(t.has(move)&&!['drought','drizzle','sandstream','snowwarning'].includes(t.ability))add(item,125,'직접 설치하는 날씨의 지속 턴 연장');
 }
 if(t.has('rest')&&!t.has('sleeptalk')&&!(t.ability==='hydration'&&t.has('raindance')))add('chestoberry',112,'잠자기 직후 수면을 해제해 행동 유지');
 if(t.ability==='harvest')add('sitrusberry',155,'수확으로 회복 열매를 재사용');
 if(t.has('shellsmash'))add('whiteherb',140,'껍질깨기의 방어·특수방어 하락 복구');
 if(t.has('endure')&&t.has('reversal'))add('liechiberry',155,'버티기·기사회생과 저HP 공격 강화 연계');
 if(t.ability==='quickfeet')add('toxicorb',160,'맹독으로 속보·객기 활성화');
 if(t.ability==='poisonheal')add('toxicorb',160,'포이즌힐 활성화');
 if(t.ability==='guts')add('flameorb',150,'근성 활성화로 물리 공격 강화');
 if(t.ability==='sturdy')add('custapberry',!t.recovery&&(t.has('explosion')||t.moves.some(m=>['stealthrock','spikes'].includes(m.id)))?125:80,'옹골참으로 버틴 뒤 같은 우선도 내 행동 선점');
 if(t.has('acrobatics'))add('flyinggem',155,'비행주얼 소모 후 애크러뱃 강화');
 if(t.ability==='unburden'&&!t.has('reversal')){
  const m=t.attack.find(m=>t.species.types.includes(m.type));if(m)add(dex.toID(m.type)+'gem',150,'주얼 소모로 곡예 활성화');
 }
 if(t.ability==='multiscale')add('leftovers',145,'멀티스케일을 재활성화하는 HP 유지');
 if(t.attack.length>=2||(t.setup&&t.attack.length>=1)){
  add('lifeorb',t.support?70:103+(t.species.baseStats.atk+t.species.baseStats.spa)/200+(t.ability==='magicguard'||t.ability==='sheerforce'?30:0),'구애 없이 공격 강화'+(['magicguard','sheerforce'].includes(t.ability)?' 및 특성 연계':''));
  if(new Set(t.attack.map(m=>m.type)).size>=2)add('expertbelt',t.support?72:88,'복수 타입 견제 기술의 약점 타격 강화');
  if(t.physical.length>=2)add('muscleband',79,'물리 기술 위력 강화로 공격 범위 유지');
  if(t.special.length>=2)add('wiseglasses',79,'특수 기술 위력 강화로 공격 범위 유지');
  if(t.physical.length>=2&&t.special.length<=1)add('choiceband',/choice band|choice attacker/i.test(t.role)?125:102,'공격 기술 중심 물리 화력 강화');
  if(t.special.length>=2&&t.physical.length<=1)add('choicespecs',/choice specs/i.test(t.role)?125:102,'공격 기술 중심 특수 화력 강화');
  add('choicescarf',/choice scarf/i.test(t.role)?132:92,'공격 기술 중심 스피드 보완');
  if(t.ability!=='sturdy'&&!t.recovery&&!t.has('substitute')&&(!t.attack.some(m=>m.recoil)||t.hazards)&&(!t.support||t.hazards))add('focussash',t.species.nfe||t.hazards||t.ability==='magicguard'?119+Math.max(0,300-t.species.baseStats.hp-t.species.baseStats.def-t.species.baseStats.spd)/10:84,'첫 행동·기점 확보를 위한 일격 생존');
  for(const type of new Set(t.attack.map(m=>m.type)))if(typeItems[type])add(typeItems[type],t.species.types.includes(type)?82:68,'실제 사용하는 '+type+' 타입 공격 강화');
 }
 if(t.moves.some(m=>m.accuracy!==true&&m.accuracy<90))add('widelens',83,'명중률이 낮은 공격·변화 기술의 안정성 보완');
 if(t.ability!=='levitate'&&dex.getImmunity('Ground',t.species)&&dex.getEffectiveness('Ground',t.species)>0)add('airballoon',t.support?94:85,'땅 약점의 일시적 무효화로 행동 기회 확보');
 if(t.species.types.includes('Dragon')&&dex.getEffectiveness('Ice',t.species)>0)add('yacheberry',t.setup?104:82,'얼음 약점 완화로 강화·행동 기회 확보');
 if(t.species.types.includes('Dark')&&dex.getEffectiveness('Fighting',t.species)>0)add('chopleberry',t.support?104:82,'격투 약점 완화로 역할 수행 보장');
 // Preserve reviewed recommendations only when the fixed four moves can use them.
 const recommended=(reference.members[p.id]?.recommendedItems||[]).map(dex.toID);
 for(const choice of map.values())if(recommended.includes(choice.item))choice.score+=8;
 return [...map.values()].sort((a,b)=>b.score-a.score||(a.item<b.item?-1:a.item>b.item?1:0));
}
function assignTeam(candidates){
 if(candidates.some(c=>!c.length))throw Error('No role-compatible item candidates');
 candidates=candidates.map(c=>c.slice().sort((a,b)=>b.score-a.score||(a.item<b.item?-1:a.item>b.item?1:0)));
 let best=null,bestScore=-Infinity;
 const upper=Array(candidates.length+1).fill(0);
 for(let i=candidates.length-1;i>=0;i--)upper[i]=upper[i+1]+candidates[i][0].score;
 function visit(index,used,chosen,score){
  if(index===candidates.length){if(score>bestScore){bestScore=score;best=chosen.slice();}return;}
  if(score+upper[index]<=bestScore)return;
  for(const c of candidates[index])if(!used.has(c.item)){
   used.add(c.item);chosen.push(c);visit(index+1,used,chosen,score+c.score);chosen.pop();used.delete(c.item);
  }
 }
 visit(0,new Set(),[],0);if(!best)throw Error('No unique role-compatible team assignment');
 return best;
}
function applyRoleItems(catalog,dex){
 for(const encounter of catalog.encounters){
  const chosen=assignTeam(encounter.team.map(p=>itemCandidates(p,dex)));
  encounter.team.forEach((p,index)=>{
   const choice=chosen[index],r=reference.members[p.id];
   p.item=choice.item;
   p.evidence={...p.evidence,itemAdapted:!r.recommendedItems.map(dex.toID).includes(p.item),
    itemOptimization:{version:VERSION,role:r.role,reason:choice.reason,score:choice.score}};
  });
 }
 return catalog;
}
module.exports={VERSION,RED_LOCKS,traits,suitability,itemCandidates,assignTeam,applyRoleItems};
