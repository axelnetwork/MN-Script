# MN-Setup Guide (Follow below Steps)

wget -q https://raw.githubusercontent.com/axelnetwork/MN-Script/master/AXEL-MN.sh

sudo chmod +x AXEL-MN.sh

./AXEL-MN.sh

When prompted to Enter your AXEL_Utility_Token Masternode GEN Key.

Paster your Masternode GEN Key and press enter

Wait till Node is fully Synced with blockchain. For check enter below command.

axel_utility_token-cli getinfo

When Node Fully Synced enter below command for check masternode status.

axel_utility_token-cli masternode status
