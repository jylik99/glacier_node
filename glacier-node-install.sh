#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to check if command was successful
check_error() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error occurred. Operation stopped.${NC}"
        exit 1
    fi
}

# Function to check if Docker is installed and running
check_docker() {
    if command -v docker &> /dev/null; then
        if systemctl is-active --quiet docker; then
            return 0  # Docker is installed and running
        else
            echo -e "${YELLOW}Docker is installed but not running. Starting Docker...${NC}"
            sudo systemctl start docker
            check_error
            return 0
        fi
    fi
    return 1  # Docker is not installed
}

# Function to show menu
show_menu() {
    clear
    echo -e "${GREEN}Glacier Node Management Menu${NC}"
    echo "=========================="
    echo "1) Install node"
    echo "2) Show logs"
    echo "3) Check status"
    echo "4) Show update-service logs"
    echo "5) Delete node"
    echo "=========================="
    echo -e "Enter your choice (Ctrl+C to exit): "
}

# Function to install node
install_node() {
    echo -e "${GREEN}Starting Glacier node installation...${NC}"

    # Update system packages
    echo -e "${GREEN}Updating system packages...${NC}"
    sudo apt update
    sudo apt upgrade -y
    check_error

    # Check if Docker is installed
    if ! check_docker; then
        echo -e "${GREEN}Docker not found. Installing Docker...${NC}"
        
        # Install Docker dependencies
        echo -e "${GREEN}Installing Docker dependencies...${NC}"
        sudo apt install -y ca-certificates curl gnupg lsb-release
        check_error

        # Set up Docker repository
        echo -e "${GREEN}Setting up Docker repository...${NC}"
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        check_error

        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker
        echo -e "${GREEN}Installing Docker...${NC}"
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        check_error

        # Start and enable Docker service
        echo -e "${GREEN}Starting Docker service...${NC}"
        sudo systemctl enable docker
        sudo systemctl start docker
        check_error
    else
        echo -e "${GREEN}Docker is already installed and running${NC}"
    fi

    # Get private key from user
    echo -e "${YELLOW}Please enter your private key:${NC}"
    read PRIVATE_KEY

    # Remove 0x prefix if present
    PRIVATE_KEY=${PRIVATE_KEY#0x}

    # Validate private key format
    if [[ ! $PRIVATE_KEY =~ ^[a-fA-F0-9]{64}$ ]]; then
        echo -e "${RED}Invalid private key format. Please enter a 64-character hexadecimal string.${NC}"
        exit 1
    fi

    # Run Glacier verifier
    echo -e "${GREEN}Starting Glacier verifier...${NC}"
    docker run -d -e PRIVATE_KEY=$PRIVATE_KEY --name glacier-verifier docker.io/glaciernetwork/glacier-verifier:v0.0.3
    check_error

    # Install Watchtower
    echo -e "${GREEN}Installing Watchtower for automatic updates...${NC}"
    docker run -d \
        --name glacier-watchtower \
        -v /var/run/docker.sock:/var/run/docker.sock \
        containrrr/watchtower \
        --interval 3600 \
        --cleanup \
        glacier-verifier
    check_error

    echo -e "${GREEN}Installation completed successfully!${NC}"
    read -p "Press Enter to return to menu..."
}

# Function to show logs
show_logs() {
    if docker ps -q -f name=glacier-verifier >/dev/null; then
        echo -e "${GREEN}Showing Glacier node logs (Ctrl+C to exit):${NC}"
        docker logs -f glacier-verifier
    else
        echo -e "${RED}Glacier node is not running!${NC}"
        read -p "Press Enter to return to menu..."
    fi
}

# Function to show Watchtower logs
show_watchtower_logs() {
    if docker ps -q -f name=glacier-watchtower >/dev/null; then
        echo -e "${GREEN}Showing Watchtower logs (Ctrl+C to exit):${NC}"
        docker logs -f glacier-watchtower
    else
        echo -e "${RED}Watchtower is not running!${NC}"
        read -p "Press Enter to return to menu..."
    fi
}

# Function to remove node
remove_node() {
    echo -e "${YELLOW}Removing Glacier node components...${NC}"
    
    # Stop and remove containers
    if docker ps -a -q -f name=glacier-watchtower >/dev/null; then
        echo "Stopping and removing Watchtower container..."
        docker stop glacier-watchtower
        docker rm -f glacier-watchtower
    fi
    
    if docker ps -a -q -f name=glacier-verifier >/dev/null; then
        echo "Stopping and removing Glacier container..."
        docker stop glacier-verifier
        docker rm -f glacier-verifier
    fi

    # Remove images
    echo "Removing Docker images..."
    docker rmi glaciernetwork/glacier-verifier:v0.0.3 2>/dev/null
    docker rmi containrrr/watchtower:latest 2>/dev/null

    # Clean up container directories
    echo "Cleaning up container directories..."
    sudo rm -rf /var/lib/docker/containers/*glacier-verifier* 2>/dev/null
    sudo rm -rf /var/lib/docker/containers/*glacier-watchtower* 2>/dev/null
    
    echo -e "${GREEN}Node removal completed${NC}"
    read -p "Press Enter to return to menu..."
}

# Function to check status
check_status() {
    echo -e "${GREEN}Checking node status...${NC}"
    
    # Check Glacier node
    if docker ps -q -f name=glacier-verifier >/dev/null; then
        echo -e "Glacier node: ${GREEN}Running${NC}"
        docker ps -f name=glacier-verifier --format "ID: {{.ID}}\nImage: {{.Image}}\nStatus: {{.Status}}\nCreated: {{.CreatedAt}}"
    else
        echo -e "Glacier node: ${RED}Not running${NC}"
    fi
    
    echo ""
    
    # Check Watchtower
    if docker ps -q -f name=glacier-watchtower >/dev/null; then
        echo -e "Watchtower: ${GREEN}Running${NC}"
        docker ps -f name=glacier-watchtower --format "ID: {{.ID}}\nStatus: {{.Status}}\nCreated: {{.CreatedAt}}"
    else
        echo -e "Watchtower: ${RED}Not running${NC}"
    fi
    
    read -p "Press Enter to return to menu..."
}

# Main loop
while true; do
    show_menu
    read choice

    case $choice in
        1) install_node ;;
        2) show_logs ;;
        3) check_status ;;
        4) show_watchtower_logs ;;
        5) remove_node ;;
        *) show_menu ;;
    esac
done