#!/bin/bash

result="Not installed"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if /usr/bin/which -s brew; then
  result=$(/usr/bin/which -a brew | sort | uniq)
fi

echo "<result>${result}</result>"
