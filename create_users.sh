#!/bin/bash

# Variables
LOG_FILE="/home/ubuntu/sysops/var/log/user_management.log"
PASSWORD_FILE="/home/ubuntu/sysops/var/secure/user_passwords.txt"
USER_FILE=$1
GROUPADD="/usr/sbin/groupadd"
USERADD="/usr/sbin/useradd"
CHPASSWD="/usr/sbin/chpasswd"
USERMOD="/usr/sbin/usermod"

# Ensure necessary directories exist
mkdir -p /home/ubuntu/sysops/var/log
mkdir -p /home/ubuntu/sysops/var/secure

# Validate username and group
validate_name() {
  local NAME=$1
  if [[ ! "$NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "Invalid name: $NAME" | tee -a $LOG_FILE
    exit 1
  fi
}

# Generate random password
generate_password() {
  < /dev/urandom tr -dc A-Za-z0-9 | head -c 12
}

# Read the user file line by line
while IFS=";" read -r username groups; do
  # Remove whitespace
  username=$(echo "$username" | xargs)
  groups=$(echo "$groups" | xargs)

  # Validate username
  validate_name "$username"

  # Create user-specific group
  if ! getent group "$username" > /dev/null 2>&1; then
    sudo $GROUPADD "$username"
    echo "Group $username created" | tee -a $LOG_FILE
  else
    echo "Group $username already exists" | tee -a $LOG_FILE
  fi

  # Check if user exists
  if ! id -u "$username" > /dev/null 2>&1; then
    # Generate password
    password=$(generate_password)

    # Create the user with their own group and home directory
    sudo $USERADD -m -g "$username" -s /bin/bash "$username"
    echo "$username:$password" | sudo $CHPASSWD
    echo "User $username created with home directory and assigned to group $username" | tee -a $LOG_FILE

    # Set appropriate permissions for home directory
    sudo chmod 700 /home/"$username"
    sudo chown "$username:$username" /home/"$username"

    # Log the password securely
    echo "$username,$password" >> $PASSWORD_FILE
  else
    echo "User $username already exists" | tee -a $LOG_FILE
  fi

  # Add user to additional groups
  if [ ! -z "$groups" ]; then
    IFS=',' read -ra ADDR <<< "$groups"
    for group in "${ADDR[@]}"; do
      group=$(echo "$group" | xargs) # Remove whitespace
      validate_name "$group"
      if ! getent group "$group" > /dev/null 2>&1; then
        sudo $GROUPADD "$group"
        echo "Group $group created" | tee -a $LOG_FILE
      fi
      sudo $USERMOD -aG "$group" "$username"
      echo "User $username added to group $group" | tee -a $LOG_FILE
    done
  fi
done < "$USER_FILE"
