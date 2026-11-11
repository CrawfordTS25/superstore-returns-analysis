import json,sys,os,re
def walk(acts,depth,out):
    for n,a in (acts or {}).items():
        t=a.get('type');ra=list((a.get('runAfter') or {}).items())
        extra=''
        inp=a.get('inputs',{}) if isinstance(a.get('inputs'),dict) else {}
        h=inp.get('host',{})
        if h: extra=h.get('operationId','')
        p=inp.get('parameters',{})
        if isinstance(p,dict):
            tbl=p.get('table') or p.get('dataset') and p.get('table')
            if tbl: extra+=' table='+str(tbl)[:40]
            if '$filter' in p: extra+=' filter='+str(p['$filter'])[:120]
        rc=a.get('runtimeConfiguration',{})
        if rc: extra+=' rc='+json.dumps(rc)[:80]
        out.append('  '*depth+f"{n} [{t}] {extra} after={[(k,v) for k,v in ra]}"[:260])
        for k in ('actions',):
            if k in a: walk(a[k],depth+1,out)
        if 'else' in a: out.append('  '*depth+' ELSE:'); walk(a['else'].get('actions'),depth+1,out)
        if 'cases' in a:
            for c,v in a['cases'].items(): out.append('  '*depth+' CASE '+c); walk(v.get('actions'),depth+1,out)
        if 'default' in a: walk(a['default'].get('actions'),depth+1,out)
for f in sys.argv[1:]:
    d=json.load(open(f));df=d['properties']['definition']
    print('=====',os.path.basename(f)[:60])
    for tn,tv in df['triggers'].items(): print('TRIGGER',tn,tv.get('type'),json.dumps(tv.get('recurrence') or tv.get('inputs',{}).get('schema',''))[:200],json.dumps(tv.get('runtimeConfiguration',{})))
    out=[];walk(df['actions'],0,out);print('\n'.join(out))
