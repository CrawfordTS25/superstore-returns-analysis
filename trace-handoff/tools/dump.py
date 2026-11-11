import json,sys,os,re
def short(v,n=400):
    s=v if isinstance(v,str) else json.dumps(v)
    s=re.sub(r'\s+',' ',s); return s if len(s)<=n else s[:n]+'…'
def walk(acts,d,out):
    for n,a in (acts or {}).items():
        t=a.get('type'); ra=a.get('runAfter') or {}
        out.append('  '*d+f"## {n} [{t}] runAfter={ {k:v for k,v in ra.items()} }")
        for k in ('runtimeConfiguration','limit','expression'):
            if k in a: out.append('  '*d+f"   {k}: {short(a[k],600)}")
        inp=a.get('inputs')
        if isinstance(inp,dict):
            h=inp.get('host',{}); 
            if h: out.append('  '*d+f"   op: {h.get('operationId')}")
            p=inp.get('parameters')
            if isinstance(p,dict):
                for k,v in p.items():
                    if k in('dataset',): continue
                    if k=='item' and isinstance(v,dict):
                        for ik,iv in v.items(): out.append('  '*d+f"   item.{ik} = {short(iv,300)}")
                    else: out.append('  '*d+f"   {k} = {short(v,500)}")
            else:
                out.append('  '*d+f"   inputs: {short({k:v for k,v in inp.items() if k!='host'},700)}")
        elif inp is not None: out.append('  '*d+f"   inputs: {short(inp,700)}")
        if 'actions' in a: walk(a['actions'],d+1,out)
        if 'else' in a: out.append('  '*d+'  -- ELSE'); walk(a['else'].get('actions'),d+1,out)
        if 'cases' in a:
            for c,v in a['cases'].items(): out.append('  '*d+f'  -- CASE {c}: {short(v.get("case"))}'); walk(v.get('actions'),d+1,out)
        if 'default' in a: out.append('  '*d+'  -- DEFAULT'); walk(a['default'].get('actions'),d+1,out)
for f in sys.argv[2:]:
    df=json.load(open(f))['properties']['definition']; out=[]
    for tn,tv in df['triggers'].items(): out.append(f"TRIGGER {tn}: {short(tv,1500)}")
    walk(df['actions'],0,out)
    nm=os.path.basename(f).split('-')[1]
    open(os.path.join(sys.argv[1],nm+'.txt'),'w').write('\n'.join(out))
