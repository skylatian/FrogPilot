#!/usr/bin/bash

export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1

if [ -z "$AGNOS_VERSION" ]; then
  export AGNOS_VERSION="10.1"
fi

export STAGING_ROOT="/data/safe_staging"

# Retrofit: force Toyota Corolla fingerprint, skip firmware query
export FINGERPRINT="TOYOTA COROLLA"
export SKIP_FW_QUERY=1

eval "$(/data/openpilot/frogpilot/system/environment_variables)"
