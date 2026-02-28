import os
import re
from typing import Dict, Any, Optional, List

def parse_timing(file_path: str) -> Dict[str, Any]:
    if not os.path.exists(file_path):
        return {'setup': None, 'hold': None}
    
    with open(file_path, 'r') as f:
        content = f.read()
    
    paths = content.split('Startpoint:')
    timing_data: Dict[str, Any] = {'setup': None, 'hold': None}
    
    for path in paths[1:]:
        type_match = re.search(r'Path Type:\s+(\w+)', path)
        slack_match = re.search(r'(-?[\d.]+)\s+slack \((MET|VIOLATED)\)', path, re.IGNORECASE)
        if type_match and slack_match:
            ptype = type_match.group(1).lower()
            data = {'slack': float(slack_match.group(1)), 'status': slack_match.group(2).upper()}
            if ptype == 'max': # Setup
                if timing_data['setup'] is None or data['slack'] < timing_data['setup']['slack']:
                    timing_data['setup'] = data
            elif ptype == 'min': # Hold
                if timing_data['hold'] is None or data['slack'] < timing_data['hold']['slack']:
                    timing_data['hold'] = data
                    
    return timing_data

def parse_summary(file_path: str) -> Dict[str, str]:
    stats = {}
    if not os.path.exists(file_path):
        return stats
    
    with open(file_path, 'r') as f:
        for line in f:
            if 'Target Freq' in line:
                stats['target_freq'] = line.split(':')[-1].strip()
            if 'Die Size' in line:
                stats['die_size'] = line.split(':')[-1].strip()
    return stats

def parse_congestion(file_path: str) -> int:
    if not os.path.exists(file_path):
        return 0
    with open(file_path, 'r') as f:
        return len(re.findall(r'violation type:', f.read()))

def parse_power(file_path: str) -> Optional[str]:
    if not os.path.exists(file_path):
        return None
    with open(file_path, 'r') as f:
        for line in f:
            if line.startswith('Total') and 'Watts' not in line:
                parts = line.split()
                if len(parts) >= 5:
                    try:
                        return f"{float(parts[4])*1000:.2f} mW"
                    except ValueError:
                        continue
    return None

def parse_skew(file_path: str) -> Optional[str]:
    if not os.path.exists(file_path):
        return None
    with open(file_path, 'r') as f:
        match = re.search(r'([\d.]+)\s+setup skew', f.read())
        if match:
            return f"{match.group(1)} ns"
    return None

def parse_violations(file_path: str) -> Dict[str, int]:
    counts = {'max_slew': 0, 'max_cap': 0, 'max_fanout': 0}
    if not os.path.exists(file_path):
        return counts
    
    with open(file_path, 'r') as f:
        content = f.read()
        
    sections = re.split(r'\n(max \w+)\n', content)
    current_sec = ""
    for item in sections:
        if item in ['max slew', 'max capacitance', 'max fanout']:
            current_sec = item
        else:
            v_count = len(re.findall(r'\(VIOLATED\)', item))
            if current_sec == 'max slew': counts['max_slew'] = v_count
            elif current_sec == 'max capacitance': counts['max_cap'] = v_count
            elif current_sec == 'max fanout': counts['max_fanout'] = v_count
            
    return counts

def generate_report():
    report_dir = 'pnr/reports'
    signoff_dir = os.path.join(report_dir, 'signoff')
    
    summary_stats = parse_summary(os.path.join(signoff_dir, 'summary.rpt'))
    timing_stats = parse_timing(os.path.join(signoff_dir, 'timing_final.rpt'))
    congestion_count = parse_congestion(os.path.join(report_dir, '05_congestion.rpt'))
    power_val = parse_power(os.path.join(signoff_dir, 'power.rpt'))
    skew_val = parse_skew(os.path.join(signoff_dir, 'clock_skew.rpt'))
    vio_counts = parse_violations(os.path.join(signoff_dir, 'violations.rpt'))
    
    with open(os.path.join(report_dir, 'SUMMARY.md'), 'w') as f:
        f.write("# ASIC Implementation Summary Dashboard\n\n")
        
        f.write("## 📊 Current Status\n\n")
        f.write("| Metric | Value | Status |\n")
        f.write("| :--- | :--- | :--- |\n")
        
        if timing_stats:
            setup = timing_stats.get('setup')
            hold = timing_stats.get('hold')
            if setup:
                status_emoji = "✅" if setup['status'] == "MET" else "❌"
                f.write(f"| Worst Setup Slack | {setup['slack']} ns | {status_emoji} {setup['status']} |\n")
            if hold:
                status_emoji = "✅" if hold['status'] == "MET" else "❌"
                f.write(f"| Worst Hold Slack | {hold['slack']} ns | {status_emoji} {hold['status']} |\n")
        
        f.write(f"| Clock Skew | {skew_val or 'N/A'} | Info |\n")
        f.write(f"| Total Power | {power_val or 'N/A'} | Info |\n")
        f.write(f"| Congestion Violations | {congestion_count} | {'⚠️ Warning' if congestion_count > 0 else '✅ Clean'} |\n")
        f.write(f"| Max Slew Violations | {vio_counts['max_slew']} | {'❌ FAIL' if vio_counts['max_slew'] > 0 else '✅ Clean'} |\n")
        f.write(f"| Max Cap Violations | {vio_counts['max_cap']} | {'❌ FAIL' if vio_counts['max_cap'] > 0 else '✅ Clean'} |\n")
        f.write(f"| Max Fanout Violations | {vio_counts['max_fanout']} | {'❌ FAIL' if vio_counts['max_fanout'] > 0 else '✅ Clean'} |\n")
        f.write(f"| Target Frequency | {summary_stats.get('target_freq', 'N/A')} | Info |\n")
        f.write(f"| Die Size | {summary_stats.get('die_size', 'N/A')} | Info |\n")
        
        f.write("\n## 💡 Insights & Recommendations\n\n")
        
        # Timing Insights
        setup = timing_stats.get('setup')
        if setup and setup['status'] == "MET":
            slack = setup['slack']
            current_period = 20.0 
            min_period = current_period - slack
            max_freq = 1000.0 / min_period
            f.write(f"### 🚀 Clock Frequency Optimization\n")
            f.write(f"- **Current Slack:** {slack} ns\n")
            f.write(f"- **Estimated Max Freq:** {max_freq:.1f} MHz\n")
            f.write(f"- **Recommendation:** You can safely increase the clock frequency to roughly **{max_freq*0.9:.1f} MHz**.\n\n")
        
        # Hold/DRV Issues
        has_drvs = any(v > 0 for v in vio_counts.values())
        hold = timing_stats.get('hold')
        if (hold and hold['status'] == "VIOLATED") or has_drvs:
            f.write(f"### 🛠️ Physical Design Fixes Required\n")
            if hold and hold['status'] == "VIOLATED":
                f.write(f"- **Hold Violation:** Worst slack is {hold['slack']} ns. This will prevent silicon from working.\n")
            if vio_counts['max_fanout'] > 0:
                f.write(f"- **Max Fanout:** {vio_counts['max_fanout']} violations found. Buffering is needed on high-fanout nets (like clkbuf outputs).\n")
            if vio_counts['max_cap'] > 0 or vio_counts['max_slew'] > 0:
                f.write(f"- **DRV Violations:** Max Slew ({vio_counts['max_slew']}) or Cap ({vio_counts['max_cap']}) failed. Check long routes or weak drivers.\n")
            f.write(f"- **Recommended Command:** Run `repair_design` and `repair_timing -hold` in OpenROAD.\n\n")

        # Area Insights
        f.write(f"### 📏 Area Optimization\n")
        if congestion_count == 0 and not has_drvs:
            f.write(f"- **Recommendation:** Since congestion and DRVs are zero, we can consider shrinking the die area by 10-20%.\n")
        else:
            f.write(f"- **Action Required:** There are significant physical violations ({congestion_count} congestion, {sum(vio_counts.values())} DRVs). Do **NOT** shrink the die area; focus on resolving these bottlenecks first.\n")

if __name__ == "__main__":
    generate_report()
    print("Summary report generated at pnr/reports/SUMMARY.md")
