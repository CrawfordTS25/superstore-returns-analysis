import json,sys,os
def topo(acts):
    names=list(acts); done=[]
    while len(done)<len(names):
        prog=False
        for n in names:
            if n in done: continue
            if all(p in done for p in (acts[n].get('runAfter') or {})): done.append(n); prog=True
        if not prog: done+=[n for n in names if n not in done]; break
    return done
def walk(acts,path,out):
    out.append(f"\n[{path}]")
    for i,n in enumerate(topo(acts),1):
        a=acts[n]; ra=a.get('runAfter') or {}
        out.append(f"  {i:>3}. {n}  ({a['type']})" + (f"  runAfter={ {k:v for k,v in ra.items()} }" if ra else ''))
    for n in topo(acts):
        a=acts[n]
        if 'actions' in a and a['actions']: walk(a['actions'],path+' > '+n+(' [YES]' if a['type']=='If' else ''),out)
        if 'else' in a and a['else'].get('actions'): walk(a['else']['actions'],path+' > '+n+' [NO]',out)
        for c,v in (a.get('cases') or {}).items():
            if v.get('actions'): walk(v['actions'],path+' > '+n+f' [CASE {c}]',out)
        if a.get('default',{}).get('actions'): walk(a['default']['actions'],path+' > '+n+' [DEFAULT]',out)
for f in sys.argv[2:]:
    df=json.load(open(f))['properties']['definition']; out=[]
    walk(df['actions'],'ROOT',out)
    open(os.path.join(sys.argv[1],os.path.basename(f).split('-')[1]+'.order.txt'),'w').write('\n'.join(out).lstrip())
