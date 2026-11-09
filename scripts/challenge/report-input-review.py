import hashlib,json
from pathlib import Path
import numpy as np
root=Path(__file__).resolve().parents[2];work=root/'build/challenge-training'
old=json.loads((root/'BattleEngine/challenge-policy-v1.json').read_text());new=json.loads((root/'BattleEngine/challenge-policy.json').read_text());data=json.loads((work/'examples.json').read_text())
held=[s for s in data['samples'] if int(hashlib.sha256(s['game'].encode()).hexdigest()[:8],16)%5==0]
def agreement(weights,width):
 return sum(int(np.argmax(np.asarray(s['x'])[:,:width]@np.asarray(weights)))==s['y'] for s in held)/len(held)
old_dev=json.loads((work/'ai-review-development-v1.json').read_text())['metrics'];old_reg=json.loads((work/'ai-review-v1.json').read_text())['metrics']
selected=next(row for row in new['calibration']['development'] if row['alpha']==new['calibration']['selectedAlpha'])
report={'date':'2026-11-06','featureVersion':new['featureVersion'],'featureCount':len(new['features']),
 'modelSHA256':hashlib.sha256((root/'BattleEngine/challenge-policy.json').read_bytes()).hexdigest(),
 'legacyModelSHA256':hashlib.sha256((root/'BattleEngine/challenge-policy-v1.json').read_bytes()).hexdigest(),
 'dataset':{'games':len(data['games']),'actions':len(data['samples']),'trainGames':new['training']['trainGames'],'evaluationGames':new['training']['evaluationGames'],'evaluationDecisions':len(held),'examplesSHA256':hashlib.sha256((work/'examples.json').read_bytes()).hexdigest()},
 'replayAgreement':{'legacy':agreement(old['weights'],32),'selected':agreement(new['weights'],len(new['features']))},
 'development':{'legacyWins':old_dev['wins']+old_reg['wins'],'selectedWins':sum(m['wins'] for m in selected['development']),'episodes':81,'selectedAlpha':new['calibration']['selectedAlpha']},
 'freshAudit':{'legacy':json.loads((work/'ai-review-final-v1.json').read_text())['metrics'],'selected':json.loads((work/'ai-review-final-v2.json').read_text())['metrics'],'usedForSelection':False},
 'inputSensitivity':json.loads((work/'ai-input-sensitivity.json').read_text()),
 'limitations':['Opponent speed is a public neutral-stat estimate; no hidden IV/EV/nature/item/ability access.','Fixed independent battles against a public-damage baseline are not human ladder or 27-fight campaign performance.','A fresh 54-game audit gives 33 legacy wins and 32 selected wins; no win-rate improvement is established.','Legacy checkpoints retain the v1 module and exact original model bytes until that encounter ends.'],
 'selection':'Rejected fully updated candidates with lower development performance; freeze original 32 learned priors, fit 16 state/action interactions to public replays, then choose a conservative blend using development seeds 2000/4000. Fresh audit uses seeds 12000, shift 11.'}
report['limitations'][2]=f"Fresh 54-game audit: {report['freshAudit']['legacy']['wins']} legacy wins, {report['freshAudit']['selected']['wins']} selected wins. This does not establish a win-rate improvement."
path=root/'docs/reference/challenge/ai-input-review.json';path.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['dataset','replayAgreement','development']},indent=2))
