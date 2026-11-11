import json,sys
df=json.load(open(sys.argv[1]))['properties']['definition']
def scope(acts,path):
    # topo order with runAfter
    names=list(acts); done=[];
    while len(done)<len(names):
        prog=False
        for n in names:
            if n in done: continue
            if all(p in done for p in (acts[n].get('runAfter') or {})): done.append(n); prog=True
        if not prog: done+= [n for n in names if n not in done]; break
    print(path+':'); 
    for n in done: print('   ',n, acts[n]['type'], {k:v for k,v in (acts[n].get('runAfter') or {}).items()})
scope(df['actions'],'ROOT')
a=df['actions']
for k in sys.argv[2:]:
    node=a
    for part in k.split('/'):
        if part=='else': node=node['else']['actions']
        else: node=node[part]['actions'] if 'actions' in node.get(part,{}) else node[part]
    scope(node,k)
