import logging
import socket
import sys

import atten
import crossconnect
import pmon
import _tl1

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
ch = logging.StreamHandler()
ch.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
ch.setFormatter(formatter)
logger.addHandler(ch)

class SessionError(Exception):
    """
        Exception raised for errors during the session interaction.
    """
    def __init__(self, message = None):
        """
            :param message: explanation of the error.
            :type message: string
        """
        #super(SessionError, self).__init__('Failed to use the Session functionality: {0}'.format(message))
        self.message = message

class Session(object):
    _port = 3082
    def __init__(self, username, host='localhost'):
        """
            Initializes a session object.

            :param username: the name of the user for the session being established.
            :type username: string or None

            :param host: the host address of the switch.
            :type host: string or None
        """
        self.host = host
        self.username = username
        self.socket = None

    def __enter__(self):
        self.login(self.username, self.password)
        return self

    def __exit__(self, type, value, traceback):
        self.logout()

    def _parseTl1Error(self, tl1Func):
    	return tl1Func(self.socket, SessionError())

    def _splitlines(self):
        self._parseTl1Error(_tl1._splitlines)

    def _check_error(self):
        self._parseTl1Error(_tl1._check_error)

    def _impexp_check_error(self):
        self._parseTl1Error(_tl1._impexp_check_error)

    def login(self, password, opr=None):
        """
            This function logs the user into the configuration session.

            :param password: the password credential of the user.
            :type password: string or None

            :returns: None
            :rtype: None

            See also :meth:`logout`.
        """
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            self.socket.connect((self.host, self._port))
        except socket.error as err:
            logger.error("Invalid IP address\n")
            exit(1)
        tl1_cmd = 'act-user::%s:%d::%s;\n' % (self.username, _tl1._ctag, password)
        self.socket.sendall(tl1_cmd)
        if opr == 'import' or opr == 'export':
            self._impexp_check_error()
        else:
            logger.info(tl1_cmd)
            self._check_error()
        tl1_cmd = 'opr-arc-eqpt::repmgr:%d::ind;\n' % (_tl1._ctag)
        #logger.info(tl1_cmd)
        self.socket.sendall(tl1_cmd)
        self.socket.recv(1024)
        #self._check_error()
        return self.socket

    def logout(self, opr=None):
        """
            This function logs the user out of the configuration session.

            :returns: None
            :rtype: None

            See also :meth:`login`.
        """
        tl1_cmd = 'canc-user::%s:%d:;\n' % (self.username, _tl1._ctag)
        self.socket.sendall(tl1_cmd)
        if opr == 'import' or opr == 'export':
            self._impexp_check_error()
        else:
            logger.info(tl1_cmd)
            self._check_error()
        self.socket.close()

    def crossConnection(self):
        """
            This function returns a cross connection instance that can be used
            for the Optical Cross Connect (OXC) functionality.

            :returns: the object that represents the cross-connections.
            :rtype: CrossConnection

            :raises CrossConnectionError: if the cross connection functionality is not supported on the switch.

            See also :meth:`attenuation`, :meth:`powerMonitor` and :class:`CrossConnection`.
        """
        return crossconnect.CrossConnection(self)

    def attenuation(self):
        """
            This function returns an attenuation instance that can be used for
            the Variable Optical Attenuation (VOA) functionality.

            :returns: the object that represents the attenuation.
            :rtype: Attenuation

            :raises AttenuationError: if the attenuation functionality is not supported on the switch.

            See also :meth:`crossConnection`, :meth:`powerMonitor` and :class:`Attenuation`.
        """
        return atten.Attenuation(self)

    def powerMonitor(self):
        """
            This function returns a power monitor instance that can be used for
            the Optical Power Monitor (OPM) functionality.

            :returns: the object that represents the power monitor.
            :rtype: PowerMonitor

            :raises PowerMonitorError: if the power monitor functionality is not supported on the switch.

            See also :meth:`crossConnection`, :meth:`attenuation` and :class:`PowerMonitor`.
        """
        return pmon.PowerMonitor(self)

