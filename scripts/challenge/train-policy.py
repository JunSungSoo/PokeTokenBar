#!/usr/bin/env python3
"""Fit a shared action-ranking policy to real BW replays. Split entire games, never turns."""
import argparse,hashlib,json
from pathlib import Path
import numpy as np
p=argparse.ArgumentParser();p.add_argument('--input',type=Path,default=Path('build/challenge-training/examples.json'));p.add_argument('--output',type=Path,default=Path('BattleEngine/challenge-policy.json'));p.add_argument('--epochs',type=int,default=240);p.add_argument('--freeze-prior',action='store_true');p.add_argument('--warm-start',type=Path);p.add_argument('--prior-strength',type=float,default=.002);a=p.parse_args()
d=json.loads(a.input.read_text());samples=d['samples'];dim=len(d['features']);width=max(len(s['x']) for s in samples)
X=np.zeros((len(samples),width,dim));mask=np.zeros((len(samples),width),dtype=bool);y=np.array([s['y'] for s in samples]);test=np.array([int(hashlib.sha256(s['game'].encode()).hexdigest()[:8],16)%5==0 for s in samples])
for i,s in enumerate(samples):X[i,:len(s['x'])]=s['x'];mask[i,:len(s['x'])]=True
assert np.isfinite(X).all() and test.any() and (~test).any()
weights=np.zeros(dim)
warm=None
if a.warm_start:
 warm=json.loads(a.warm_start.read_text())
 by_name=dict(zip(warm['features'],warm['weights']))
 by_name['speciesSpeedPrior']=by_name.get('speed',0);by_name['offensePrior']=by_name.get('offense',0)
 weights=np.asarray([by_name.get(name,0) for name in d['features']],dtype=float)
prior=weights.copy()
def evaluate(w,selection):
 x=X[selection];m=mask[selection];labels=y[selection];scores=np.einsum('nkd,d->nk',x,w);scores[~m]=-1e9;scores-=scores.max(axis=1,keepdims=True);p=np.exp(scores);p/=p.sum(axis=1,keepdims=True)
 return float(-np.log(p[np.arange(len(labels)),labels]+1e-15).mean()),float((p.argmax(axis=1)==labels).mean()),p
trainX=X[~test];trainY=y[~test]
for epoch in range(a.epochs):
 loss,accuracy,prob=evaluate(weights,~test);prob[np.arange(len(trainY)),trainY]-=1
 gradient=np.einsum('nk,nkd->d',prob,trainX)/len(trainY)+a.prior_strength*(weights-prior)
 if a.freeze_prior and warm:gradient[:len(warm["features"])]=0
 weights-=.15*gradient
trainLoss,trainAcc,_=evaluate(weights,~test);testLoss,testAcc,_=evaluate(weights,test)
metrics={'trainDecisions':int((~test).sum()),'evaluationDecisions':int(test.sum()),'trainGames':len({s['game'] for i,s in enumerate(samples) if not test[i]}),'evaluationGames':len({s['game'] for i,s in enumerate(samples) if test[i]}),'trainLoss':trainLoss,'evaluationLoss':testLoss,'trainActionAccuracy':trainAcc,'evaluationActionAccuracy':testAcc,'uniformEvaluationAccuracy':float((1/mask[test].sum(axis=1)).mean()),'method':'linear action ranking with masked conditional softmax and L2 regularization','seed':0,'epochs':a.epochs,'warmStartSHA256':hashlib.sha256(a.warm_start.read_bytes()).hexdigest() if a.warm_start else None,'priorStrength':a.prior_strength,'frozenPrior':a.freeze_prior,'note':'Action agreement on incomplete public replay observations is not battle win rate or proof of expert strength.'}
# These artifacts are a genuine small-sample model, not a claim of expert-level play.
model={'schemaVersion':1,'featureVersion':d['featureVersion'],'features':d['features'],'weights':weights.tolist(),'training':metrics,'sourceDatasetSHA256':hashlib.sha256(a.input.read_bytes()).hexdigest()}
# A separate learned ranking head selects a lead using only the unordered public teams.
lead=d['leadSamples'];lx=np.asarray([s['x'] for s in lead],dtype=float);ly=np.asarray([s['y'] for s in lead]);lt=np.array([int(hashlib.sha256(s['game'].encode()).hexdigest()[:8],16)%5==0 for s in lead]);lw=np.zeros(lx.shape[2])
for epoch in range(a.epochs):
 scores=lx[~lt]@lw;scores-=scores.max(axis=1,keepdims=True);prob=np.exp(scores);prob/=prob.sum(axis=1,keepdims=True);prob[np.arange((~lt).sum()),ly[~lt]]-=1
 lw-=.15*(np.einsum('nk,nkd->d',prob,lx[~lt])/(~lt).sum()+.002*lw)
model['lead']={'featureVersion':'bw-public-lead-v1','features':d['leadFeatures'],'weights':lw.tolist(),'trainingExamples':int((~lt).sum()),'evaluationExamples':int(lt.sum()),'evaluationAccuracy':float(((lx[lt]@lw).argmax(axis=1)==ly[lt]).mean())}
a.output.write_text(json.dumps(model,indent=2)+'\n')
report=a.output.with_suffix('.training.json');report.write_text(json.dumps({'metrics':metrics,'games':d['games'],'limitations':['198 public BW OU replays requested; retained subset after format checks.','Own move candidates are limited to moves revealed during the replay; unseen opponent moves are never features.','Public HP is rounded; exact EVs, IVs, items and full move availability are not reconstructed.','Learned linear policy is a baseline; no expert-strength or campaign win-rate claim.']},indent=2)+'\n')
print(json.dumps(metrics,indent=2))
