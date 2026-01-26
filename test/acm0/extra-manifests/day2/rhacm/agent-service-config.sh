#!/bin/bash

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Function to wait for CRD to exist and be established
wait_for_crd() {
    local crd_name="$1"
    local timeout="${2:-300}"  # default 5 minutes
    local elapsed=0
    local interval=10
    
    echo "Waiting for CRD $crd_name to be created and established..."
    
    while [ $elapsed -lt $timeout ]; do
        # First check if CRD exists
        if oc get crd "$crd_name" >/dev/null 2>&1; then
            echo "CRD $crd_name found, checking if established..."
            # Now wait for it to be established
            if oc wait --for condition=established crd "$crd_name" --timeout=30s >/dev/null 2>&1; then
                echo "CRD $crd_name is established and ready"
                return 0
            fi
        else
            echo "CRD $crd_name not found yet, waiting... (${elapsed}s/${timeout}s)"
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo "ERROR: Timeout waiting for CRD $crd_name after ${timeout}s"
    return 1
}

# Wait for agentserviceconfig CRD to exist and be established
if ! wait_for_crd "agentserviceconfigs.agent-install.openshift.io" 180; then
    echo "ERROR: AgentServiceConfig CRD is not available"
    echo "Please ensure ACM/RHACM with MultiCluster Engine is properly installed"
    exit 1
fi

# Apply agent-service-config.yaml
echo "Applying AgentServiceConfig..."
oc apply -f $basedir/agent-service-config.yaml

echo "AgentServiceConfig applied successfully!"

