### import json file and create connectoins in json file ###
from pypolatis.crossconnect import CrossConnection
from pypolatis.session import Session
import argparse



def import_connections(host, username, password, filename):
    """
    import json and create  cross-connections using imported json file

    Args:
    host : Switch IP address
    username : Valid username
    password : Valid password
    filename : JSON file
    """
    ses = Session(username, host)
    login = ses.login(password, opr = 'import')
    add = CrossConnection(login)
    add.import_connection(filename)
    ses.logout(opr = 'import')

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
                        help='Enter your previously exported JSON file; eg: \"connections.json\"')
    args = parser.parse_args()
    import_connections(args.host, args.username, args.password, args.filename)

