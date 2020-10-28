import logging
import socket
import sys
import re

logger = logging.getLogger(__name__)

logger.setLevel(logging.INFO)
ch = logging.StreamHandler()
ch.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
ch.setFormatter(formatter)
logger.addHandler(ch)

class _Tl1Error(Exception):
    """
        Exception raised for errors during the configuration
    """
    def __init__(self, code, message):
        """
            code: error code
            message: error message
        """
        super(_Tl1Error, self).__init__('Failed to interact with the switch: {0}'.format(message))
        self.code = code
        self.message = message

_portsep = ':'
_valsep = ','
_ctag = 123

def _list(portList):
    """
        This function returns a TL1 compatible port list format by
        resolving the details about the '&' and '&&' concatenation types.

        portList: list of the ports specified
    """
    try:
        egrSymbol = re.split(r'[\d]', portList)
    except Exception as err:
        egrSymbol = []
        portList = portList
    if ',' in egrSymbol:
        portList = portList.split(',')
        return '&'.join(str(v) for v in portList) if portList is not None else ''
    elif '-' in egrSymbol:
        portList = portList.split('-')
        return '&&'.join(str(v) for v in portList) if portList is not None else ''
    elif type(portList) == str:
        return portList
    elif type(portList) == list:
        return '&'.join(str(v) for v in portList) if portList is not None else ''
    else:
        logger.error('Provide the correct range of port list\n')
        exit(1)

_linesize = 4096
_linesep = '\r\n'
_responseCodeIdentifier = 'M  %d ' % _ctag
_ok_resp = 'COMPLD'
_respsep = ';'
_autonomousCodeIdentifier = 'A '

def _splitlines(socket, e):
    """
        Yields the next valid line to be parsed. If there is no expected
        output other than success or failure, it just returns that line.

	There are two different messages types that we need to handle:

	http://en.wikipedia.org/wiki/Transaction_Language_1#TL1_output_message

	and

	http://en.wikipedia.org/wiki/Transaction_Language_1#TL1_autonomous_message
    """
    sys.stdout.flush() 
    buff = socket.recv(_linesize)
    logger.info("buff : %s" % buff)
    buff = buff.split(_linesep, 2)[2]
    ign_sep = False
    while True:
        line, separator, buff = buff.partition(_linesep)
        logger.debug(line)
        if line == _respsep:
            if ign_sep:
        	ign_sep = False 
            break
        elif line.startswith(_responseCodeIdentifier):
            ign_sep = False
            if line[len(_responseCodeIdentifier):] == _ok_resp:
                continue
            else:
                errorCode, errorString, buff = buff.split(_linesep, 2)
                logger.debug('%s (%s)' % (errorCode, errorString))
                errorString = errorString.strip()[3:-3]
                if errorCode == 'IICM':
                    errorString = 'Not supported on this switch'
                #e.setMessage(errorString)
                elif 'PICC' in errorCode:
                    logger.error("Authentication failure\n")
                    exit(1)
                else:
                    pass
                return
                #raise e
        elif line.startswith(_autonomousCodeIdentifier):
            ign_sep = True
            continue
        elif separator:
            yield line
        else:
            buff += socket.recv(_linesize)


def _impexp_splitlines(socket, e):
    """
        Yields the next valid line to be parsed. If there is no expected
        output other than success or failure, it just returns that line.

        There are two different messages types that we need to handle:

        http://en.wikipedia.org/wiki/Transaction_Language_1#TL1_output_message

        and

        http://en.wikipedia.org/wiki/Transaction_Language_1#TL1_autonomous_message
    """
    sys.stdout.flush()
    buff = socket.recv(_linesize)
    #logger.info("buff : %s" % buff)
    buff = buff.split(_linesep, 2)[2]
    ign_sep = False
    while True:
        line, separator, buff = buff.partition(_linesep)
        logger.debug(line)
        if line == _respsep:
            if ign_sep:
                ign_sep = False
            break
        elif line.startswith(_responseCodeIdentifier):
            ign_sep = False
            if line[len(_responseCodeIdentifier):] == _ok_resp:
                continue
            else:
                errorString = 'Empty'
                errorCode, errorString, buff = buff.split(_linesep, 2)
                logger.debug('%s (%s)' % (errorCode, errorString))
                errorString = errorString.strip()[3:-3]
                if errorCode == 'IICM':
                    errorString = 'Not supported on this switch'
                #e.setMessage(errorString)
                elif 'PICC' in errorCode:
                    logger.error("Authentication failure. Please check the username or password.\n")
                    exit(1)
                elif 'IIAC' in errorCode:
                    logger.error(errorString)
                    logger.error("Import operation failed. HINT: Please check the port number.\n") 
                    exit(1)
                else:
                    pass
                return
                #raise e
        elif line.startswith(_autonomousCodeIdentifier):
            ign_sep = True
            continue
        elif separator:
            yield line
        else:
            buff += socket.recv(_linesize)

def _impexp_check_error(socket, e):
    """
        This function checks whether or not there has been any error occured
        for the given command sent.
    """
    for line in _impexp_splitlines(socket, e):
        pass

def _check_error(socket, e):
    """
        This function checks whether or not there has been any error occured
        for the given command sent.
    """
    for line in _splitlines(socket, e):
        pass

def _alarm_type(alarmType):
    """
        This function returns the string feasible for the corresponding TL1
        commands.
    """
    return '::type=%s' % 'LOS' if alarmType == None else alarmType

def _reverse(reverse):
    """
        This function returns the string feasible for the reverse TL1 commands.
    """
    return '' if reverse == False else 'rev'

def _reversePortsCtagAlarmType(reverse, ports, alarmType):
    """
        This function returns the string feasible for the power monitor commands
        that contain the reverse, ports, ctag and alarm type information.
    """
    return '%spmon::%s:%d:%s\n' % (_reverse(reverse), _list(ports), _ctag, _alarm_type(alarmType))
