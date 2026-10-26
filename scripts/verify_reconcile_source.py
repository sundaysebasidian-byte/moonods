#!/usr/bin/env python3
"""Current-checkout JS workflow smoke test; no Office or registry-install claim."""
import argparse
import csv
import datetime
from decimal import Decimal
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    out = a.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('REPORT_', 'RECONCILE_', 'ODS_'))}
    steps = []
    report = {'status': 'FAIL', 'scope': __doc__, 'steps': steps}

    def run(name, example, extra, expected=0, reason=None):
        cmd = ['moon', 'run', '--target', 'js', '--deny-warn', '-j', '1', example]
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        r = subprocess.run(cmd, cwd=ROOT, env={**env, **extra}, capture_output=True,
                           text=True, timeout=120)
        (out / (name + '.stdout.txt')).write_text(r.stdout)
        (out / (name + '.stderr.txt')).write_text(r.stderr)
        steps.append({'name': name, 'command': cmd, 'environment_overrides': extra,
                      'started_utc': started, 'exit_code': r.returncode,
                      'expected_exit': expected, 'expected_reason': reason})
        require(r.returncode == expected, name + ' unexpected exit')
        require(reason is None or reason in r.stdout + r.stderr,
                name + ' wrong refusal reason')
        return r.stdout

    try:
        source, result = out / 'input', out / 'output'
        source.mkdir()
        result.mkdir()
        run('generate', 'examples/procurement', {'REPORT_OUTPUT': str(source)})
        changes = out / 'changes.csv'
        changes.write_text('订单,数量\r\nSYN-202610-001,5\r\nSYN-202610-004,0\r\n', newline='')
        config = {'RECONCILE_INPUT': str(source / 'procurement.ods'),
                  'RECONCILE_CHANGES': str(changes), 'RECONCILE_OUTPUT': str(result),
                  'RECONCILE_ACCEPT_LOSS': '1'}
        text = run('reconcile', 'examples/reconcile', config)
        require('total_cents=100650 changed_orders=2 over_budget_departments=1' in text,
                'business summary mismatch')
        with (result / 'details.csv').open(newline='') as stream:
            rows = list(csv.reader(stream, strict=True))
        require(len(rows) == 5 and all(len(row) == 9 for row in rows), 'CSV shape')
        total = sum(Decimal(row[3]) * Decimal(row[4]) * 100 for row in rows[1:])
        require(total == 100650 and '😀' in rows[1][2] and '\n' in rows[1][8]
                and '"' in rows[1][8], 'CSV independent decimal/Unicode oracle')
        with (result / 'audit.csv').open(newline='') as stream:
            audit = list(csv.reader(stream, strict=True))
        require([row[0] for row in audit[1:]] == ['SYN-202610-001', 'SYN-202610-004'],
                'audit order mismatch')
        protected = [source / 'procurement.ods', *result.iterdir()]
        before = {str(path): sha(path) for path in protected}
        for name, data, reason in [
            ('unknown-order', '订单,数量\r\nUNKNOWN,1\r\n', 'unknown amendment order'),
            ('extra-column', '订单,数量\r\nSYN-202610-001,5,extra\r\n',
             'CSV rows must have equal column counts'),
        ]:
            changes.write_text(data, newline='')
            input_hash = sha(changes)
            run(name, 'examples/reconcile', config, expected=1, reason=reason)
            require(all(sha(Path(path)) == digest for path, digest in before.items())
                    and sha(changes) == input_hash, 'refusal changed input or old output')
            require(not list(result.glob('.moonods-*.tmp')), 'temporary output left behind')
        report.update(status='PASS', total_cents=int(total),
                      generated_sha256={p.name: sha(p) for p in result.iterdir()},
                      refusal_preserves_inputs_and_outputs=True)
    except Exception as error:
        report['error'] = str(error)
    (out / 'result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
