### Retrieve cross connection between ingress and egress ports ###
from pypolatis.crossconnect import CrossConnection
from pypolatis.session import Session
import argparse



def get_connections(host, username, password, ports):
    """
    Retrieve cross-connections using single/multiple ports

    Args:
    host : Switch IP address
    username : Valid username
    password : Valid password
    ports : Valid ports    
    """
    ses = Session(username, host)
    login = ses.login(password)
    get = CrossConnection(login)
    get.connection(ports)
    ses.logout()

if __name__ == '__main__':
    """
    Main
    """
    parser = argparse.ArgumentParser()
    requiredNamed = parser.add_argument_group('required arguments')
    requiredNamed.add_argument('--host', action='store', required=True,
                        help='IP address of the switch')
    requiredNamed.add_argument('--username', action='store', required=True,
                        help='Username')
    requiredNamed.add_argument('--password', action='store', required=True,
                        help='Password')
    requiredNamed.add_argument('--ports', action='store', required=True,
                        help='\'prt\' or \'prt1,prt2\' or \'prt1-prt2\' or ALL; eg: 1 or 49,50 or 1-53 or ALL')
    args = parser.parse_args()
    get_connections(args.host, args.username, args.password, args.ports)

