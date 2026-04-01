#!/bin/bash

# ===============================
# Colors
# ===============================
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
NC="\e[0m"

# ===============================
# Pretty Line
# ===============================
line() {
  echo -e "${CYAN}--------------------------------------------------${NC}"
}

# ===============================
# Banner
# ===============================
echo -e "${BLUE}"
echo "   ____                  _       "
echo "  / ___|  ___ _ ____   _(_) ___  "
echo "  \___ \ / _ \ '__\ \ / / |/ _ \ "
echo "   ___) |  __/ |   \ V /| | (_) |"
echo "  |____/ \___|_|    \_/ |_|\___/ "
echo -e "${NC}"
line

# ===============================
# Input Domain
# ===============================
read -p "$(echo -e ${YELLOW}Enter domain: ${NC})" DOMAIN

if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}❌ Domain is required${NC}"
  exit 1
fi

line

# ===============================
# Check Domain Owner
# ===============================
echo -e "${BLUE}🔍 Checking domain owner...${NC}"
OWNER=$(whmapi1 getdomainowner domain=$DOMAIN 2>/dev/null | grep owner: | awk '{print $2}')

if [[ -z "$OWNER" ]]; then
  echo -e "${YELLOW}⚠️ Domain not assigned to any user (or metadata broken)${NC}"
else
  echo -e "${GREEN}✅ Domain belongs to user: $OWNER${NC}"
fi

line

# ===============================
# Check Domain Userdata
# ===============================
echo -e "${BLUE}📦 Fetching domain userdata...${NC}"
whmapi1 domainuserdata domain=$DOMAIN

line

# ===============================
# Handle leftover userdata files
# ===============================
if [[ -n "$OWNER" ]]; then
  USERDATA_PATH="/var/cpanel/userdata/$OWNER"

  echo -e "${BLUE}🔎 Checking userdata files in ${USERDATA_PATH}${NC}"

  FILES=$(ls $USERDATA_PATH 2>/dev/null | grep $DOMAIN)

  if [[ -z "$FILES" ]]; then
    echo -e "${GREEN}✅ No leftover userdata files found${NC}"
  else
    echo -e "${YELLOW}⚠️ Found leftover userdata files:${NC}"
    echo "$FILES"

    echo -ne "${YELLOW}Delete these files? (y/n): ${NC}"
    read CONFIRM

    if [[ "$CONFIRM" == "y" ]]; then
      rm -f $USERDATA_PATH/${DOMAIN}*
      echo -e "${GREEN}🧹 Cleaned userdata files${NC}"
    else
      echo -e "${RED}❌ Skipped deleting files${NC}"
    fi
  fi
fi

line

# ===============================
# Update cPanel configs
# ===============================
echo -e "${BLUE}🔄 Updating cPanel domain configs...${NC}"
/scripts/updateuserdomains
/scripts/rebuildhttpdconf
/scripts/updateuserdatacache --force
echo -e "${GREEN}✅ cPanel configs updated${NC}"

line

# ===============================
# Check DNS ownership
# ===============================
echo -e "${BLUE}🔍 Checking DNS ownership...${NC}"
/scripts/whoowns $DOMAIN

line

# ===============================
# Optional DNS zone check
# ===============================
echo -ne "${YELLOW}Do you want to check DNS zone manually? (y/n): ${NC}"
read DNSCHECK

if [[ "$DNSCHECK" == "y" ]]; then
  echo -e "${BLUE}📂 Checking DNS zone files...${NC}"
  ls /var/named | grep $DOMAIN

  if [[ $? -eq 0 ]]; then
    echo -e "${YELLOW}⚠️ DNS zone exists, remove manually or via WHM${NC}"
  else
    echo -e "${GREEN}✅ No DNS zone found for $DOMAIN${NC}"
  fi
fi

line

# ===============================
# Optional: Search in userdata globally
# ===============================
echo -ne "${YELLOW}Do you want to search the domain in all userdata files? (y/n): ${NC}"
read GLOBALSEARCH

if [[ "$GLOBALSEARCH" == "y" ]]; then
  echo -e "${BLUE}🔎 Searching in /var/cpanel/userdata...${NC}"
  grep -r "$DOMAIN" /var/cpanel/userdata 2>/dev/null
fi

line

# ===============================
# Done
# ===============================
echo -e "${GREEN}🎉 Done! If issue still exists:${NC}"
echo -e "${CYAN}➡️ Check Panel Alpha logs (Download System Logs)${NC}"
echo -e "${CYAN}➡️ Search domain inside logs${NC}"

line
echo -e "${GREEN}✔️ Script completed successfully${NC}"
