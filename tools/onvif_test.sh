#!/usr/bin/env bash
# Query a virtual ONVIF camera the way UniFi Protect does (WS-UsernameToken).
# onvif-server does not validate the ONVIF login, so dummy credentials are fine.
# Usage: ./onvif_test.sh 192.168.1.31 [8081]
IP="${1:?camera IP}"; PORT="${2:-8081}"
env_xml(){ printf '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Header><wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"><wsse:UsernameToken><wsse:Username>test</wsse:Username><wsse:Password>test</wsse:Password></wsse:UsernameToken></wsse:Security></s:Header><s:Body>%s</s:Body></s:Envelope>' "$1"; }
post(){ curl -s -m 8 -H 'Content-Type: application/soap+xml' --data "$(env_xml "$2")" "http://$IP:$PORT/onvif/$1"; }

echo "== Device information / time"
for body in '<GetDeviceInformation xmlns="http://www.onvif.org/ver10/device/wsdl"/>' '<GetSystemDateAndTime xmlns="http://www.onvif.org/ver10/device/wsdl"/>'; do
  post device_service "$body" | grep -oE '<(tds|tt):(Manufacturer|Model|FirmwareVersion|Hour|Minute)>[^<]*' | tr '\n' ' '; echo
done
echo "== Profiles"
post media_service '<GetProfiles xmlns="http://www.onvif.org/ver10/media/wsdl"/>' | grep -oE '(token="[^"]*"|<(tt|trt):(Name|Encoding|Width|Height|FrameRateLimit|BitrateLimit)>[^<]*)' | tr '\n' ' '; echo
echo "== Stream URI"
post media_service '<GetStreamUri xmlns="http://www.onvif.org/ver10/media/wsdl"><ProfileToken>main_stream</ProfileToken></GetStreamUri>' | grep -oE '<(tt|trt):Uri>[^<]*'; echo
