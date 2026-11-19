#!/bin/bash

security create-keychain -p "" zero.keychain
security set-keychain-settings -u zero.keychain
security add-certificates -k zero.keychain "Developer ID Application: Zero (5NN7GUYB6T).cer"
security add-certificates -k zero.keychain "Developer ID Certification Authority.cer"
security import "Zero.p12" -P "" -k zero.keychain -A
security import "Zero.pem" -k zero.keychain
