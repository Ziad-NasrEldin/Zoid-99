Status: ready-for-agent

# Add source repair and reconnection workflows

Connect each Source Health Ledger state to one truthful repair action.
Cover setup-required, disconnected, delayed, rate-limited, unavailable, missing, cached, and live states.
Do not erase the last known evidence during a failed refresh.

Implementation evidence: all required written repair states, state-specific actions, retained activity and evidence, reconnect and disconnect workflows, and fixture tests are included in the issue 002/006 delivery commit.
Native visual acceptance and credentialed provider checks remain human/live gates.
