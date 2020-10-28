### Create cross connection between ingress and egress ports ###
from pypolatis.crossconnect import CrossConnection
from pypolatis.session import Session
import argparse



def add_connections(host, username, password, inputports, outputports):
    """
    Create cross-connections using single/multiple ports.
    This will also take care of moving the connection between ports.

    Arguments:
    host       : Switch IP address
    username   : Valid username
    password   : Valid password
    inputports : Valid ingressports    
    outputports: Valid egressports
    """
    ses = Session(username, host)
    login = ses.login(password)
    add = CrossConnection(login)
    add.setConnection(inputports,outputports)
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
    requiredNamed.add_argument('--inports', action='store', required=True,
                        help='\'ingPrt\' or \'ingPrt1,ingPrt2\' or \'ingPrt1-ingPrt2\'; eg: 1 or 1,2 or 1-5')
    requiredNamed.add_argument('--outports', action='store', required=True,
                        help='\'egPrt\' or \'egPrt1,egPrt2\' or \'egPrt1-egPrt2\'; eg: 49 or 49,50 or 49-53')
    args = parser.parse_args()
    add_connections(args.host, args.username, args.password, args.inports, args.outports)
