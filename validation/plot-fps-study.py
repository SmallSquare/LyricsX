#!/usr/bin/env python3
"""Standalone scientific chart, generated only after measurements have finished."""
import json,statistics,sys
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'outputs/fps-study';r=json.loads((OUT/'results.json').read_text())
for path in ['/System/Library/Fonts/PingFang.ttc','/System/Library/Fonts/STHeiti Light.ttc']:
 if Path(path).exists():font_manager.fontManager.addfont(path);plt.rcParams['font.family']=font_manager.FontProperties(fname=path).get_name();break
plt.rcParams.update({'axes.unicode_minus':False,'font.size':10,'axes.spines.top':False,'axes.spines.right':False,'savefig.facecolor':'#f6f8fb'})
fig,axs=plt.subplots(2,2,figsize=(13.8,9.2),layout='constrained');fig.set_facecolor('#f6f8fb')
xs=[0,24,30,60,90,120]
def group(f):return [a for a in r['rows'] if (a['mode']=='static' if f==0 else a['mode']=='native' and a['target_fps']==f)]
def series(k):
 vals=[[a[k] for a in group(f) if a.get(k) is not None] for f in xs]
 ys=[statistics.mean(a) if a else np.nan for a in vals]
 lo=[y-min(a) if a else 0 for y,a in zip(ys,vals)];hi=[max(a)-y if a else 0 for y,a in zip(ys,vals)]
 return np.array(ys),[lo,hi]
def line(ax,k,label,color):
 y,e=series(k);ax.errorbar(xs,y,yerr=e,fmt='o-',capsize=4,lw=2,color=color,label=label);return y
orig=[a for a in r['rows'] if a['mode']=='original']
ax=axs[0,0];y=line(ax,'LyricsX_cpu','自绘 LyricsX','#1267c4')
if orig:
 oy=statistics.mean(a['LyricsX_cpu'] for a in orig);ax.axhline(oy,color='#d24b3e',ls='--',label=f'原版默认动画：{oy:.1f}%')
for x,v in zip(xs,y):ax.annotate(f'{v:.1f}%',(x,v),xytext=((-8 if x==24 else 8 if x==30 else 0),10),textcoords='offset points',ha='center',fontsize=9)
ax.set(title='① 完整 LyricsX 的 CPU',ylabel='CPU（100% = 一个核心）');ax.legend(loc='best');ax.set_ylim(bottom=0)
ax=axs[0,1]
for k,l,c in [('MenuBarAgent_delta_cpu','MenuBarAgent','#9655c7'),('WindowServer_delta_cpu','WindowServer','#de8b24'),('ControlCenter_delta_cpu','ControlCenter','#229478')]:line(ax,k,l,c)
ax.axhline(0,c='#999',lw=.8);ax.set(title='② 系统组件 CPU 差值（含后台干扰）',ylabel='相对前后关闭基线，百分点');ax.legend(loc='best')
ax=axs[1,0];line(ax,'delta_soc_w','CPU + GPU + ANE 芯片功率','#1267c4');line(ax,'delta_cpu_w','CPU 功率','#229478')
if orig:
 vals=[a['delta_soc_w'] for a in orig if a.get('delta_soc_w') is not None]
 if vals:
  ax.axhspan(min(vals),max(vals),color='#d24b3e',alpha=.07)
  ax.axhline(statistics.mean(vals),color='#d24b3e',ls='--',label=f'原版芯片差值：{statistics.mean(vals):.2f} W（浅红为范围）')
ax.axhline(0,c='#999',lw=.8);ax.set(title='③ 芯片功率差值（不能推算整机耗电）',ylabel='相对前后关闭基线，W');ax.legend(loc='best')
ax.text(.98,.03,'负值与大幅波动反映后台噪声；不能解读为省电',transform=ax.transAxes,ha='right',fontsize=9,color='#a23c34')
ax=axs[1,1];cd=r['cadence'];actual=[cd.get(f'native-{f}',{}).get('mean_update_hz',np.nan) for f in xs[1:]]
ax.plot(xs[1:],xs[1:],'--',c='#bbb',label='目标 = 实际');ax.plot(xs[1:],actual,'o-',c='#1267c4',lw=2,label='实际文字位置更新')
for x,v in zip(xs[1:],actual):
 if not np.isnan(v):ax.annotate(f'{v:.1f}',(x,v),xytext=(0,8),textcoords='offset points',ha='center')
o=cd.get('original-None',{})
if o:ax.axhline(o['mean_update_hz'],color='#d24b3e',ls='--',label=f'原版实际更新：{o["mean_update_hz"]:.1f}/秒')
ax.set(title='④ 滚动期间的实际更新频率',ylabel='位置更新次数 / 秒');ax.legend(loc='best');ax.set_ylim(bottom=0)
for ax in axs.flat:ax.grid(alpha=.18);ax.set_xticks(xs);ax.set_xticklabels(['静态','24','30','60','90','120']);ax.set_xlabel('自绘方案目标 fps（静态 = 0）')
fig.suptitle('LyricsX 菜单栏滚动：更新频率、CPU 与芯片功率',fontsize=20,weight='bold')
fig.supxlabel('M4 · macOS 27.0 (26A428) · 183 pt / 14 pt · 同一英文长句每 8 秒换句 · CPU 100% = 一个核心\n每档两轮 × 32 秒；误差线为两轮范围，非置信区间（静态芯片功率仅一轮）。菜单栏含折叠状态；位置更新 ≠ 面板呈现帧率。',fontsize=10)
for ext in ['png','svg','pdf']:fig.savefig(OUT/f'fps-cpu-power.{ext}',dpi=180)
