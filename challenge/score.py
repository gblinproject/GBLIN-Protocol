#!/usr/bin/env python3
"""
BEAT OUR SHIELD — official scorer (deterministic, offline).
Exact replica of GBLIN V6 refreshWeights() run on 10.1y of real BTC/ETH history.

Usage:
    python3 score.py <fullSlashDrawdownBps> <slashMultiplier> <slowPeakDecayPerDayBps>
Example (current on-chain config):
    python3 score.py 3000 2000 15
Score = Calmar ratio (CAGR / MaxDrawdown) of the shielded basket. Higher wins.
Bounds (timelock-settable): full 2000..9000 · slash 500..5000 · slow 1..50
"""
import sys, csv

BPS = 10_000
BASE = dict(
    base_w={"btc": 4500, "eth": 4500, "usdc": 1000},
    baseCrashThresholdBps=1500, crashVolMultiplier=5000,
    minCrashBps=1500, maxCrashBps=5000, recoveryBandBps=800,
    peakDecayPerDayBps=50,
)

class Asset:
    def __init__(self, name, base_w, stable=False):
        self.name=name; self.base=base_w; self.stable=stable
        self.dyn=base_w; self.peak=0.0; self.slow=0.0
        self.lastObs=0.0; self.ewmaVolBps=0.0; self.shielded=False

def refresh_weights(assets, prices, P):
    total_slashed=0.0
    for a in assets:
        a.dyn=a.base; cp=prices[a.name]
        if a.lastObs>0:
            inst=abs(cp-a.lastObs)/a.lastObs*BPS
            a.ewmaVolBps=(inst*3 + a.ewmaVolBps*7)/10
        a.lastObs=cp
        if a.stable: continue
        if a.peak>0:
            dec=a.peak*P["peakDecayPerDayBps"]/BPS
            a.peak=a.peak-dec if dec<a.peak else cp
        if cp>a.peak: a.peak=cp
        if a.slow>0:
            sdec=a.slow*P["slowPeakDecayPerDayBps"]/BPS
            a.slow=a.slow-sdec if sdec<a.slow else cp
        if cp>a.slow: a.slow=cp
        ddF=(a.peak-cp)/a.peak*BPS if a.peak>cp else 0.0
        ddS=(a.slow-cp)/a.slow*BPS if a.slow>cp else 0.0
        drawdown=max(ddF,ddS)
        eff=P["baseCrashThresholdBps"]+a.ewmaVolBps*P["crashVolMultiplier"]/BPS
        eff=max(P["minCrashBps"],min(P["maxCrashBps"],eff))
        if (not a.shielded) and drawdown>eff: a.shielded=True
        elif a.shielded and drawdown<P["recoveryBandBps"]: a.shielded=False
        if a.shielded:
            if drawdown>=P["fullSlashDrawdownBps"]: sev=1.0
            elif drawdown>eff and P["fullSlashDrawdownBps"]>eff:
                sev=(drawdown-eff)/(P["fullSlashDrawdownBps"]-eff)
            else: sev=0.0
            keepBps=BPS - sev*(BPS-P["slashMultiplier"])
            new=a.base*keepBps/BPS
            total_slashed+=a.base-new; a.dyn=new
    if total_slashed>0:
        for a in assets:
            if a.stable and a.dyn>0: a.dyn+=total_slashed
    return {a.name:a.dyn/BPS for a in assets}

def max_drawdown(series):
    peak=series[0]; mdd=0.0
    for v in series:
        if v>peak: peak=v
        dd=(peak-v)/peak
        if dd>mdd: mdd=dd
    return mdd

def main():
    if len(sys.argv)!=4:
        print(__doc__); sys.exit(1)
    full,slash,slow = (int(x) for x in sys.argv[1:4])
    assert 2000<=full<=9000 and 500<=slash<=5000 and 1<=slow<=50, "params out of allowed bounds"
    P=dict(BASE, fullSlashDrawdownBps=full, slashMultiplier=slash, slowPeakDecayPerDayBps=slow)
    rows=list(csv.DictReader(open(__file__.rsplit('/',1)[0]+"/prices.csv")))
    A=[Asset("btc",P["base_w"]["btc"]),Asset("eth",P["base_w"]["eth"]),Asset("usdc",P["base_w"]["usdc"],True)]
    v=[10000.0]; prev=None; pw=None
    for r in rows:
        px={"btc":float(r["btc"]),"eth":float(r["eth"]),"usdc":1.0}
        w=refresh_weights(A,px,P)
        if prev is not None:
            rb=px["btc"]/prev["btc"]-1; re=px["eth"]/prev["eth"]-1
            v.append(v[-1]*(1+pw["btc"]*rb+pw["eth"]*re))
        prev=px; pw=w
    yrs=len(rows)/365.25
    fin=v[-1]; cagr=(fin/10000)**(1/yrs)-1; mdd=max_drawdown(v)
    calmar=cagr/mdd if mdd>0 else 0
    print(f"params: full={full} slash={slash} slow={slow}")
    print(f"period: {rows[0]['day']} -> {rows[-1]['day']} ({len(rows)}d)")
    print(f"final:  ${fin:,.0f}  CAGR: {cagr*100:.2f}%  MaxDD: {mdd*100:.2f}%")
    print(f"SCORE (Calmar): {calmar:.4f}")

if __name__=="__main__": main()
