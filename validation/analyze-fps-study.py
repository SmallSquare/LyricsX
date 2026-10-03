#!/usr/bin/env python3
import json,re,datetime,statistics,csv,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'outputs/fps-study'

def mean(a):return statistics.mean(a) if a else None

def parse_power():
    data=(OUT/'power-continuous.txt').read_text();records=[]
    for block in data.split('*** Sampled system activity (')[1:]:
        header=block.split(') (',1)
        try:t=datetime.datetime.strptime(header[0],'%a %b %d %H:%M:%S %Y %z').timestamp()
        except ValueError:continue
        elapsed=float(re.match(r'([\d.]+)ms elapsed',header[1])[1])/1000
        record={'start':t-elapsed,'end':t}
        for k,name in [('cpu_w','CPU Power'),('gpu_w','GPU Power'),('ane_w','ANE Power'),('soc_w','Combined Power (CPU + GPU + ANE)')]:
            m=re.search(re.escape(name)+r': (\d+) mW',block)
            if m:record[k]=int(m[1])/1000
        if 'soc_w' in record:records.append(record)
    return records

def power_for(p,records):
    # Retain only complete power sampling intervals inside a measured phase.
    a=[r for r in records if r['start']>=p['start'] and r['end']<=p['end']]
    return {k:mean([r[k] for r in a if k in r]) for k in ['cpu_w','gpu_w','ane_w','soc_w']}|{'n_power':len(a),'power_coverage':sum(r['end']-r['start'] for r in a)/(p['end']-p['start'])}

def interpolate_base(p,before,after,key):
    def at(q):return (q['start']+q['end'])/2
    def get(q):return q.get('cpu_percent',{}).get(key) if key in ['LyricsX','MenuBarAgent','WindowServer','ControlCenter'] else q.get(key)
    x,y=get(before),get(after)
    if x is None or y is None:return None
    f=(at(p)-at(before))/(at(after)-at(before));return x+(y-x)*f

def cadence():
    out={}
    for path in OUT.glob('cadence-*.json'):
        d=json.loads(path.read_text());frames=d['frames'];segments=[];current=[];prev=None
        for r in frames:
            if prev and r['x']<prev['x']-0.00001 and 0<r['t']-prev['t']<.3:
                if not current:current=[prev]
                current.append(r)
            else:
                if len(current)>5:segments.append(current)
                current=[]
            prev=r
        if len(current)>5:segments.append(current)
        durations=[s[-1]['t']-s[0]['t'] for s in segments];intervals=[b['t']-a['t'] for s in segments for a,b in zip(s,s[1:])]
        rates=[(len(s)-1)/(s[-1]['t']-s[0]['t']) for s in segments]
        if not intervals:continue
        out[path.stem.replace('cadence-','')]={'mean_update_hz':len(intervals)/sum(intervals),'median_interval_ms':statistics.median(intervals)*1000,'p10_interval_ms':sorted(intervals)[int(.1*len(intervals))]*1000,'p90_interval_ms':sorted(intervals)[int(.9*len(intervals))]*1000,'cycles_hz':rates,'active_seconds':sum(durations),'events':len(intervals),'max_screen_fps':d.get('max_screen_fps')}
    return out

def analyze():
    phases=json.loads((OUT/'phases.json').read_text());power=parse_power()
    for p in phases:p.update(power_for(p,power))
    rows=[]
    for i,p in enumerate(phases):
        if p['mode']=='off':continue
        before=next((q for q in reversed(phases[:i]) if q['mode']=='off'),None)
        after=next((q for q in phases[i+1:] if q['mode']=='off'),None)
        if not before or not after:continue
        r={'mode':p['mode'],'target_fps':p['fps'],'round':p['round'],'seconds':p['elapsed'],'power_samples':p['n_power'],'power_coverage':p['power_coverage']}
        for k,v in p['cpu_percent'].items():r[k+'_cpu']=v;r[k+'_delta_cpu']=v-interpolate_base(p,before,after,k)
        for k in ['cpu_w','gpu_w','ane_w','soc_w']:
            r[k]=p[k];base=interpolate_base(p,before,after,k);r['delta_'+k]=p[k]-base if p[k] is not None and base is not None and p['power_coverage']>.75 and before['power_coverage']>.5 and after['power_coverage']>.5 else None
        rows.append(r)
    with (OUT/'cpu-soc-results.csv').open('w') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    whole=[]
    wp=OUT/'whole-power-phases.json'
    if wp.exists():
        wph=json.loads(wp.read_text())
        for p in wph:
            # Use a new driver reading after washout, then retain its dwell time.
            refreshed=None;prev_count=None;kept=[]
            for sample in p['samples']:
                count=sample['battery'].get('system_count')
                if sample['epoch']>=p['start']+64 and count is not None and prev_count is not None and count!=prev_count and refreshed is None:
                    refreshed=sample['epoch']
                if refreshed is not None:kept.append(sample)
                prev_count=count
            if not kept:kept=[s for s in p['samples'] if s['epoch']>=p['start']+100]
            p['retained_from']=refreshed
            intervals=[];previous=None;seen_fresh=False
            for sample in p['samples']:
                b=sample['battery']
                if previous and b.get('system_count')!=previous['battery'].get('system_count'):
                    old=previous['battery'];count=b['system_count']-old['system_count'];acc=b['system_accum_mw']-old['system_accum_mw']
                    if seen_fresh and sample['epoch']>=p['start']+64 and count>0 and acc>=0:
                        intervals.append({'start':previous['epoch'],'end':sample['epoch'],'count':count,'mean_w':acc/count/1000})
                    seen_fresh=True
                    previous=sample
                elif previous is None:previous=sample
            p['system_load_intervals']=intervals
            p['system_load_w']=sum(a['mean_w']*a['count'] for a in intervals)/sum(a['count'] for a in intervals) if intervals else None
            p['system_load_w_min']=min(a['mean_w'] for a in intervals) if intervals else None
            p['system_load_w_max']=max(a['mean_w'] for a in intervals) if intervals else None
            p['battery_w']=mean([s['battery']['watts'] for s in kept]);p['battery_w_min']=min(s['battery']['watts'] for s in kept);p['battery_w_max']=max(s['battery']['watts'] for s in kept);p['unique_battery_values']=len(set(s['battery']['watts'] for s in kept))
            p['on_battery']=all(not s['battery']['external'] and not s['battery']['charging'] for s in kept)
        for i,p in enumerate(wph):
            if p['mode']=='off':continue
            before=next((q for q in reversed(wph[:i]) if q['mode']=='off'),None);after=next((q for q in wph[i+1:] if q['mode']=='off'),None)
            if not before or not after:continue
            base=interpolate_base(p,before,after,'system_load_w')
            if base is None or p['system_load_w'] is None:continue
            p['cpu_delta']={k:p['cpu_percent'][k]-interpolate_base(p,before,after,k) for k in p['cpu_percent']}
            whole.append({'mode':p['mode'],'target_fps':p['fps'],'system_load_w':p['system_load_w'],'delta_system_load_w':p['system_load_w']-base,'instant_battery_w_mean':p['battery_w'],'delta_system_load_w_min':p['system_load_w_min']-interpolate_base(p,before,after,'system_load_w_max'),'delta_system_load_w_max':p['system_load_w_max']-interpolate_base(p,before,after,'system_load_w_min'),'counter_intervals':len(p['system_load_intervals']),'unique_battery_values':p['unique_battery_values'],'on_battery':p['on_battery'],'retained_from':p['retained_from'],'cpu_percent':p['cpu_percent'],'cpu_delta':p['cpu_delta']})
    if whole:
        with (OUT/'whole-power-results.csv').open('w') as f:
            w=csv.DictWriter(f,fieldnames=[k for k in whole[0] if k not in ['cpu_percent','cpu_delta']]);w.writeheader();w.writerows({k:v for k,v in a.items() if k not in ['cpu_percent','cpu_delta']} for a in whole)
    result={'rows':rows,'cadence':cadence(),'whole':whole,'off_cpu_means':{k:mean([p['cpu_percent'][k] for p in phases if p['mode']=='off']) for k in ['LyricsX','MenuBarAgent','WindowServer','ControlCenter']},'power_samples_total':len(power),'whole_off_system_load_w':[p['system_load_w'] for p in wph if p['mode']=='off'] if wp.exists() else []}
    (OUT/'results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,ensure_ascii=False))
    return result

if __name__=='__main__':analyze()
