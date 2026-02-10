#!/usr/bin/env bash

# Copyright 2025 Universal Blue
# Copyright 2025 The Secureblue Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under the License is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and limitations under the License.

set -oue pipefail

MODULE_NAME="${1-}"
if [ -z "${MODULE_NAME}" ]; then
  echo 'MODULE_NAME is empty. Exiting...'
  exit 1
fi
if [[ "$IMAGE_NAME" == *'surface'* ]]; then
  KERNEL_NAME='kernel-surface'
else
  KERNEL_NAME='kernel'
fi

KERNEL_VERSION="$(rpm -q ${KERNEL_NAME} --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
PUBLIC_KEY_CRT_PATH='/tmp/certs/public_key.crt'
PRIVATE_KEY_PATH='/tmp/certs/private_key.priv'
SIGNING_KEY='/tmp/certs/signing_key.pem'

openssl x509 \
        -in ${PUBLIC_KEY_DER_PATH} \
        -out ${PUBLIC_KEY_CRT_PATH}
cat ${PRIVATE_KEY_PATH} \
    <(echo) ${PUBLIC_KEY_CRT_PATH} \
    >> ${SIGNING_KEY}

MODULES=/usr/lib/modules/"${KERNEL_VERSION}"/extra/"${MODULE_NAME}"/*.ko*

for MODULE in ${MODULES}; do
  MODULE_BASENAME="${MODULE:0:-3}"
  MODULE_SUFFIX="${MODULE: -3}"
  if [[ ${MODULE_SUFFIX} == '.xz' ]]; then
    xz --decompress \
       ${MODULE}
    openssl cms \
            -sign \
            -signer ${SIGNING_KEY} \
            -binary \
            -in ${MODULE_BASENAME} \
            -outform DER \
            -out "${MODULE_BASENAME}.cms" \
            -nocerts \
            -noattr \
            -nosmimecap
    /usr/src/kernels/"${KERNEL_VERSION}"/scripts/sign-file \
                    -s "${MODULE_BASENAME}.cms" \
                    sha256 \
                    "${PUBLIC_KEY_CRT_PATH}" \
                    "${MODULE_BASENAME}"
    /bin/bash './sign-check.sh' \
              ${KERNEL_VERSION} \
              ${MODULE_BASENAME} \
              ${PUBLIC_KEY_CRT_PATH}
    xz -C crc32 \
       --force \
       ${MODULE_BASENAME}
  elif [[ ${MODULE_SUFFIX} == '.gz' ]]; then
    gzip --decompress \
         ${MODULE}
    openssl cms \
            -sign \
            -signer ${SIGNING_KEY} \
            -binary \
            -in ${MODULE_BASENAME} \
            -outform DER \
            -out "${MODULE_BASENAME}.cms" \
            -nocerts \
            -noattr \
            -nosmimecap
    /usr/src/kernels/"${KERNEL_VERSION}"/scripts/sign-file \
                    -s "${MODULE_BASENAME}.cms" \
                    sha256 \
                    ${PUBLIC_KEY_CRT_PATH} \
                    ${MODULE_BASENAME}
    /bin/bash ./sign-check.sh \
              ${KERNEL_VERSION} \
              ${MODULE_BASENAME} \
              ${PUBLIC_KEY_CRT_PATH}
    gzip --best \
         --force \
         ${MODULE_BASENAME}
  else
    openssl cms \
            -sign \
            -signer ${SIGNING_KEY} \
            -binary \
            -in ${MODULE} \
            -outform DER \
            -out "${MODULE}.cms" \
            -nocerts \
            -noattr \
            -nosmimecap
    /usr/src/kernels/"${KERNEL_VERSION}"/scripts/sign-file \
                    -s "${MODULE}.cms" \
                    sha256 \
                    ${PUBLIC_KEY_CRT_PATH} \
                    ${MODULE}
    /bin/bash ./sign-check.sh \
              ${KERNEL_VERSION} \
              ${MODULE} \
              ${PUBLIC_KEY_CRT_PATH}
  fi
done
