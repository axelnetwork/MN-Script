# AXEL MN Setup Script

Usage:
```
# first (preparation) step
cd /root; rm -f ./axel-install.sh; wget https://raw.githubusercontent.com/axelnetwork/MN-Script/master/axel-install.sh && chmod u+x ./axel-install.sh
# second (installation) step (one of both commands below)
/root/axel-install.sh
mv /root/.axel/debug.log /root/.axel/debug.log-$(date +%y%m%d%H%M) && /root/axel-install.sh --upgrade && axel-cli -version
```
It will be required to enter a masternode private key on `Enter your AXEL Masternode Private Key:` prompt during the initial installation.

After script's execution just wait for a node's full sync (use `axel-cli getinfo` command for checking of blockchain status, and `axel-cli masternode status` for checking of masternode status).
