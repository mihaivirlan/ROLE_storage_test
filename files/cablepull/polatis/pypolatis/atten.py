import logging
import socket
import _tl1

logger = logging.getLogger(__name__)

class AttenuationError(Exception):
    """
        Exception raised for errors during the attenuation interaction.
    """
    def __init__(self, message = None):
        """
            :param message: explanation of the error.
            :type message: string

            See also :class:`Attenuation`.
        """
        super(AttenuationError, self).__init__('Failed to use the Attenuation functionality: {0}'.format(message))
        self.message = message

    def setMessage(self, message):
	self.message = message

class Attenuation(object):
    _mode = None
    def __init__(self, session):
        """
            Initializes a session object.

            :param session: the session object that represents the session under which the Variable Optical Attenuation (VOA) functionality is being used.
            :type session: Session

            :raises AttenuationError: if the attenuation functionality is not supported on the switch. This exception is also raised throughout the class in any method where there can be any issue.

            See also :class:`AttenuationError` and :class:`Session`.
        """
        self.session = session
        _mode = self._get_mode()
        if self._mode == 'NONE':
            raise AttenuationError('Attenuation not supported on this switch')


    def _parseTl1Error(self, tl1Func):
        return tl1Func(self.session.socket, AttenuationError())

    def _splitlines_atten(self):
        return self._parseTl1Error(_tl1._splitlines)

    def _check_error(self):
        self._parseTl1Error(_tl1._check_error)

    def _get_mode(self):
        tl1_cmd = 'rtrv-eqpt::atten:%d:::parameter=config;\n' % _tl1._ctag
        logger.info(tl1_cmd)
        self.session.socket.sendall(tl1_cmd)
        for line in self._splitlines_atten():
            self._mode = line.split('=')[1][:-1]
            return

    def mode(self):
        """
            This function is used to query the attenuation mode supported by
            the switch.

            :returns: VOA mode configured for the switch.
            :rtype: string
        """
        return self._mode

    def setSettings(self, mode, level=None, refs=None, ports=None):
        """
            This function sets the attenuation values for the switch.

            :param mode: This parameter is required and can be one of the values below. The other parameters are only valid for specific values of this parameter, as defined below.
            :type mode: string

            :param level: The attenuation level for the given mode. This parameter is optional depending on the mode parameter.
            :type level: float

            :param refs: The reference ports for relative attenuation.
            :type refs: list of integers

            :param ports: the ports for which the attenuation is being set up.
            :type ports: list of integers

            :returns: None
            :rtype: None

            NONE
                Clears the attenuation on the ports specified. level and refs are not specified for this mode.

            FIX
                Fixes the attenuation currently in force for the ports specified (i.e. stops closed-loop control of the attenuation). level and refs are not specified for this mode.

            MAX
                Sets the attenuation to maximum on the ports specified. level and refs are not specified for this mode.

            ABS
                Sets an absolute attenuation level for the ports specified. The level must be specified for this mode, but refs is not used.

            CONV
                Sets a converged absolute attenuation level for the ports specified. level must be specified for this mode, but refs is not used. Once the output power converges to the desired level, the switch fixes the attenuation (i.e. the VOA control loop is suspended).

            REL
                Sets a relative attenuation level for the ports specified. level must be specified for this mode. Note that only the VST 200 switch variant supports Relative Attenuation. For any other switch variant, attempting to specify relative mode will return error. In this mode the attenuation on each port is measured relative to a reference port. These reference ports may be explicitly provided by means of the refs parameter (one reference port for each attenuated port). Alternatively, if refs is omitted each port in the AID is attenuated with reference to the port it is connected to in the switch. For example, if port 5 is connected to port 30 and port 30 is specified in a relative attenuation command with refs omitted, then port 5 will be taken to be the reference port for the attenuation.

            See also :meth:`settings`.
        """
        data = ''
        separator=''
        if mode:
            data += 'mode=%s' % mode
            separator = _tl1._valsep
        if level:
            data += '%slevel=(%.1f)' % (separator, level)
            separator = _tl1._valsep
        if refs:
            data += '%srefs=%s' % (separator, _tl1._list(refs))

        tl1_cmd = 'set-port-atten::%s:%d:::%s;\n' % (_tl1._list(ports), _tl1._ctag, data)
        logger.info(tl1_cmd)
        self.session.socket.sendall(tl1_cmd)
        self._check_error()

    def settings(self, ports):
        """
            This function queries the attenuation settings on the ports
            specified in the corresponding argument.
            
            :param ports: The ports that the attenuation settings are queried for.
            :type ports: list of integers

            :returns: a list of items for each port, namely: mode, level and refs. The level and ref values left *None* for those ports for which they are not relevant. For example, if a port has maximum attenuation set then the reply for this port would return [(MAX,None,None)]
            :rtype: list of values

            See also :meth:`setSettings`.
        """
        tl1_cmd = 'rtrv-port-atten::%s:%d:;\n' % (_tl1._list(ports), _tl1._ctag)
        logger.info(tl1_cmd)
        self.session.socket.sendall(tl1_cmd)
        settingsList = []
        for line in self._splitlines_atten():
            port, data = line.split(_tl1._portsep)
            mode, level, ref = data[:-1].split(_tl1._valsep)
            settingsList.append((int(port.strip()[1:]), mode, float(level) if level else None, int(ref) if ref else None))
        return settingsList

    mode = property(mode, doc='Attenuation mode (string enumeration) supported by the switch')
