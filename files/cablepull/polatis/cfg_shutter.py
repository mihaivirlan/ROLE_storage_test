### Create cross connection between ingress and egress ports ###
from pypolatis.crossconnect import CrossConnection
from pypolatis.session import Session
import argparse



def add_connections(host, username, password, ports, interv):
    """
    Create cross-connections using single/multiple ports.
    This will also take care of moving the connection between ports.

    Arguments:
    host       : Switch IP address
    username   : Valid username
    password   : Valid password
    ports      : Valid ports
    interv     : Valid interval
    """
    ses = Session(username, host)
    login = ses.login(password)
    add = CrossConnection(login)
    add.setShutter(ports,interv)
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
    requiredNamed.add_argument('--interv', action='store', required=True,
                        help='\'offintv,onintvl,cycles\'; eg: 10000,300,1')
    args = parser.parse_args()
    add_connections(args.host, args.username, args.password, args.ports, args.interv)
