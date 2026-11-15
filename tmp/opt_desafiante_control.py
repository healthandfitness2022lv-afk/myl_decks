"""Optimización Desafiante Control: screening heurístico + confirmación IA buena."""
import json, glob, sys, time, random
from collections import Counter
from multiprocessing import Pool
sys.path.insert(0, '.')
from myl_sim.datos import Mazo, Tipo
from myl_sim.optimizador import pool_de, _grupo as clase
from myl_sim.meta import raciales_del_cache
BASE='OiU2a8CSLtA4IGUTmekw'
UNICAS={'Joya Amatista','Ogham','Macda Tho','Manzana Sidhe','Bola de Energía'}
OUT=sys.argv[1]
def log(estado):
    json.dump(estado, open(OUT+'.progreso.json','w',encoding='utf-8'), ensure_ascii=False, indent=1)

ms=[Mazo.from_json(json.load(open(f,encoding='utf-8'))) for f in glob.glob('cache/mazo_*.json')]
base=[m for m in ms if m.id==BASE][0]
rivales=[m for m in raciales_del_cache() if not m.sin_programar() and m.id!=BASE]
ban=json.load(open('cache/ban_list_racial.json',encoding='utf-8'))
pool,mx=pool_de(base,ms,ban=ban)
for cid,c in pool.items():
    if c.nombre in UNICAS: mx[cid]=1
bc=Counter(c.id for c in base.cartas)
nombres={c.id:c.nombre for c in pool.values()}
variantes=[('BASE',None,None)]
salen=sorted({c.id for c in base.cartas if c.id in pool})
for e in pool:
    if bc[e]>=mx[e]: continue
    for s in salen:
        if s==e or clase(pool[s])!=clase(pool[e]): continue
        variantes.append((f'-{nombres[s]} +{nombres[e]}',s,e))
def cartas_de(v):
    _,s,e=v
    if s is None: return base.cartas
    out=list(base.cartas); i=next(i for i,c in enumerate(out) if c.id==s); out[i]=pool[e]; return out

def _job(args):
    import myl_sim.busqueda_vigilia
    from myl_sim.jugadores import JUGADORES
    from myl_sim.motor import Partida
    vi, ri, k, jug = args
    cs=cartas_de(variantes[vi]); r=rivales[ri]
    s=10007*ri+k+ (500000 if jug!='heuristico' else 0)
    try:
        p=Partida((cs,r.cartas),(JUGADORES[jug](s*2),JUGADORES['heuristico'](s*2+1)),inicial=k%2,seed=s)
        g=p.jugar().ganador
    except Exception as ex:
        return (vi,ri,k,None)
    return (vi,ri,k, 1.0 if g==0 else 0.0 if g==1 else 0.5 if g!=-2 else None)

import os
CACHEF=os.environ.get('CACHEF','resultados.jsonl'); T0=time.time(); BUDGET=float(os.environ.get('BUDGET','160'))
HECHO={}
if os.path.exists(CACHEF):
    for l in open(CACHEF):
        a=json.loads(l); HECHO[tuple(a[:4])]=a[4]
class Pausa(Exception): pass
def ok(v):
    _,sa,en=variantes[v]
    return nombres[sa]!='Carmix' and nombres[en]!='Broche de Tara'
def correr(vis, ks, jug, pp, tag, res):
    jobs=[(vi,ri,k,jug) for vi in vis for ri in range(len(rivales)) for k in ks]
    pend=[j for j in jobs if j not in HECHO]
    for j in jobs:
        if j in HECHO: res.setdefault(j[0],{})[(j[1],j[2])]=HECHO[j]
    if not pend: return
    f=open(CACHEF,'a'); n=0
    it=pp.imap_unordered(_job, pend, chunksize=4 if jug=='heuristico' else 1)
    for vi,ri,k,w in it:
        res.setdefault(vi,{})[(ri,k)]=w; HECHO[(vi,ri,k,jug)]=w; f.write(json.dumps([vi,ri,k,jug,w])+'\n'); f.flush(); n+=1
        if time.time()-T0>BUDGET and n<len(pend):
            hechas=len(jobs)-len(pend)+n
            log({'etapa':tag,'hechas':hechas,'total':len(jobs)}); print('PAUSA',tag,hechas,len(jobs)); pp.terminate(); raise Pausa
    f.close()
def wr(res,vi):
    v=[w for w in res[vi].values() if w is not None]; return sum(v)/len(v)
def diff(res,vi):
    d=[res[vi][key]-res[0][key] for key in res[vi] if res[vi][key] is not None and res[0].get(key) is not None]
    m=sum(d)/len(d); sd=(sum((x-m)**2 for x in d)/(len(d)-1))**.5; return m, 1.96*sd/len(d)**.5, len(d)

def main():
    print(len(variantes),'variantes',len(rivales),'rivales',flush=True)
    import os; pp=Pool(max(2,(os.cpu_count() or 4)-2)); H={}; resumen={'variantes':len(variantes),'rivales':len(rivales)}
    vivos=list(range(len(variantes))); ks=[0,1]; etapa=0
    nxt=2
    for objetivo in (48, 14):
        correr(vivos, ks, 'heuristico', pp, f'heur {len(vivos)} var x {len(ks)}/rival', H)
        orden=sorted([v for v in vivos if v and ok(v)], key=lambda v: -diff(H,v)[0])
        resumen[f'heur_{len(ks)}']=[(variantes[v][0], *diff(H,v)) for v in orden[:60]]
        json.dump(resumen, open(OUT,'w',encoding='utf-8'), ensure_ascii=False, indent=1)
        vivos=[0]+orden[:objetivo]
        # siguientes partidas: los vivos juegan más semillas (todas las anteriores ya jugadas)
        ks=list(range(nxt, nxt*3)); nxt*=3
    correr(vivos, ks, 'heuristico', pp, f'heur final {len(vivos)} var', H)
    orden=sorted([v for v in vivos if v and ok(v)], key=lambda v: -diff(H,v)[0])
    resumen['heur_final']=[(variantes[v][0], *diff(H,v), wr(H,v)) for v in orden]
    resumen['heur_base_wr']=wr(H,0)
    json.dump(resumen, open(OUT,'w',encoding='utf-8'), ensure_ascii=False, indent=1)
    top=[0]+orden[:6]; B={}
    correr(top, [0,1], 'busqueda_vigilia', pp, f'IA buena {len(top)} var x 2/rival', B)
    resumen['ia_buena']=[(variantes[v][0], *diff(B,v), wr(B,v)) for v in top[1:]]
    resumen['ia_buena_base_wr']=wr(B,0)
    json.dump(resumen, open(OUT,'w',encoding='utf-8'), ensure_ascii=False, indent=1)
    log({'etapa':'fin'})

if __name__=='__main__':
    try: main()
    except Pausa: sys.exit(3)
