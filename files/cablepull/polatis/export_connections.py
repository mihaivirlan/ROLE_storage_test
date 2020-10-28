### Export the current state of cross-connections as json file ###
from pypolatis.crossconnect import CrossConnection
from pypolatis.session import Session
import argparse



def export_connections(host, username, password, filename):
    """
    Export current state of the cross-connections as a JSON filename.

    Args:
    host : Switch IP address
    username : Valid username
    password : Valid password
    filename : Json file
    """
    ses = Session(username, host)
    login = ses.login(password, opr = 'export')
    add = CrossConnection(login)
    add.export_connection(filename, opr = 'export')
    ses.logout(opr = 'export')

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
    requiredNamed.add_argument('--filename', action='store', required=True,
                        help='Enter a filename to export(.json will be automatically added); eg: \'connections\'')
    args = parser.parse_args()
    export_connections(args.host, args.username, args.password, args.filename)

