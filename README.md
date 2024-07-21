## What is Vaultwarden

Vaultwarden is an open-source, self-hosted password manager that offers strong encryption and user control over sensitive data. It provides a secure alternative to cloud-based password managers, allowing individuals and organizations to manage and protect their passwords and confidential information on their own servers.

**Disclaimer: The information and guidance provided here are for informational purposes only.While every effort has been made to ensure the accuracy and security of the instructions provided, there is no guarantee that self-hosted Vaultwarden will be immune to hacking or unauthorized access. Users should be aware that the security of their Vaultwarden instance ultimately depends on various factors, including server configuration, software updates, and adherence to security best practices.**

## Script Features

The script offers the following features:

### Create a New Linux User

A new Linux user account will be created where Vaultwarden will run. This ensures Vaultwarden container runs in an isolated user environment.

### Install Docker in Rootless Mode

The script will automatically install Docker in rootless mode to be used for running Vaultwarden securely.

### Install Docker Compose

As Vaultwarden will be deployed using a Docker Compose file, the script will install the Docker Compose pip3 package.

### Configure Vaultwarden Docker File

The script will handle the configuration of the Docker Compose file, automatically deploying a functional version of Vaultwarden.

### Add Cronjob

A new cronjob will be added to ensure Vaultwarden starts at system startup.


## Getting Started

For more detailed instructions and tips, please refer to the [documentation](https://www.byteninja.net/self-hosted-vaultwarden/) on my personal blog.
