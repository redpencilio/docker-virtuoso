import sys
import json

config_file = sys.argv[1]
config = {}
with open(config_file) as f:
    config = json.load(f)

graph_regex = "<{}> .$".format("|".join(config['graphs']))
grep_commands = f'egrep "{graph_regex}"'
for regex in config['graphRegexes']:
    grep_commands += f'| egrep "{regex}"'

print(grep_commands)
