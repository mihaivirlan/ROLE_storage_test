import logging
import socket
import _tl1

logger = logging.getLogger(__name__)

class PowerMonitorError(Exception):
    """
        Exception raised for errors during the power monitor interaction.
    """
    def __init__(self, message = None):
        """
            :param message: explanation of the error.
            :type message: string

            See also :class:`PowerMonitor`.
        """
        super(PowerMonitorError, self).__init__('Failed to use the Power Monitor functionality: {0}'.format(message))
        self.message = message

    def setMessage(self, message):
	self.message = message

class PowerMonitor(object):
    def __init__(self, session):
        """
            Initializes a session object.

            :param session: the session object that represents the session under which the power monitor functionality is being used.
            :type session: Session

            :raises PowerMonitorError: if the power monitor functionality is not supported on the switch. This exception is also raised throughout the class in any method where there can be any issue, e.g. invalid ports specified that do not have an optical power monitor connected to.

            See also :class:`PowerMonitorError` and :class:`Session`.
        """
        self.session = session
        self._testPowerMonitorSupport()

    def _testPowerMonitorSupport(self):
        self.ports()
        self.ports(reverse=True)

    def _parseTl1Error(self, tl1Func):
	return tl1Func(self.session.socket, PowerMonitorError())

    def _splitlines(self):
        return self._parseTl1Error(_tl1._splitlines)

    def _check_error(self):
        self._parseTl1Error(_tl1._check_error)

    def ports(self, reverse=False):
        """
            This function is used to query which ports have power monitors
            fitted, and whether they are configured as input or output power
            monitors.

            :param reverse: this parameter determines whether a forward or reverse query is sent.
            :type reverse: bool

            :returns: the list of port and mode tuples.
            :rtype: list of tuples
        """
        tl1_cmd = 'rtrv-eqpt::%spmon:%d:::parameter=config;\n' % (_tl1._reverse(reverse), _tl1._ctag)
        logger.info(tl1_cmd)
        self.session.socket.sendall(tl1_cmd)
        portModeList = []
        for line in self._splitlines():
            port, mode = line.split(_tl1._valsep)
            portModeList.append((int(port.split('=')[1]), mode.split('=')[1][:-1]))
        return portModeList

    def setConfiguration(self, ports, wavelength, offset, averageTime, reverse=False):
        """
            This function is used to configure the Power monitors for the ports
            specified in the desired direction.

            :param ports: the list of ports for which to set up the power monitor configuration.
            :type ports: list of integers

            :param wavelength: The optical power monitors need to be configured with the wavelength of light in use on each port. This is used to compensate for the wavelength dependence of power monitor response.  It is important to specify the correct wavelength for each port to ensure accurate power monitor readings.
            :type wavelength: float

            :param offset: Fixed offsets can to be added to reported power levels - specifying an offset can be used as a means of referencing the power monitors against external meters. It should be noted that the offset feature does *not* impact the behaviour of the Variable Optical Attenuation feature: attenuation settings always operate relative to the actual power monitor readings, i.e. without any user-specified offsets.
            :type offset: float

            :param averageTime: The averaging-time used by power monitors can be configured. In the table below the left-hand column shows the parameter values available and the right-hand column shows the corresponding averaging time.
            :type averageTime: integer

            +------------+---------------------+
            | atime code | Averaging time (ms) |
            +============+=====================+
            |      1     |          10         |
            +------------+---------------------+
            |      2     |          20         |
            +------------+---------------------+
            |      3     |          50         |
            +------------+---------------------+
            |      4     |         100         |
            +------------+---------------------+
            |      5     |         200         |
            +------------+---------------------+
            |      6     |         500         |
            +------------+---------------------+
            |      7     |        1000         |
            +------------+---------------------+
            |      8     |        2000         |
            +------------+---------------------+

            :returns: None
            :rtype: None
        """
        if not any([wavelength, offset, averageTime]):
            raise ValueError("At least one of the arguments has to be provided: wavelength, offset or averaging time")
        tl1_cmd = 'set-port-%spmon::%s:%d:::wave=%s,offset=%s,atime=%d;\n' % (_tl1._reverse(reverse), _tl1._list(ports), _tl1._ctag, wavelength, offset, averageTime)
        logger.info(tl1_cmd)
        self.session.socket.sendall(tl1_cmd)
        self._check_error()

    def configuration(self, ports=None, reverse=False):
        """
            This function queries the power monitor settings in the specified
            direction for the ports specified. Each tuple in the response
            returns the port number, wavelength, offset, and averaging time for
            a single port.

            :param ports: the list of ports for which to query the power monitor settings.  This defaults to all if not specified.
            :type ports: list of integers

            :param reverse: whether it is a reverse or forward power monitor query. This defaults to False if not specified, which means forward direction.
            :type reverse: bool

            :returns: the list of settings for each specified or all ports.
            :rtype: list of tuples
        """
        tl1_cmd = 'rtrv-port-%spmon::%s:%d:;\n' % (_tl1._reverse(reverse), _tl1._list(ports), _tl1._ctag)
        logger.info(tl1_cmd)
        self.session.socket.sendall(tl1_cmd)
        settingsList = []
        for line in self._splitlines():
            port, data = line.split(_tl1._portsep)
            wavelength, offset, averagingTime = data[:-1].split(_tl1._valsep)
            settingsList.append((int(port.strip()[1:]), float(wavelength), float(offset), int(averagingTime)))
        return settingsList

    def power(self, ports=None, reverse=False):
        """
            This function queries the measured power on the ports specified.

            :param ports: the list of ports for which to query the power monitor power settings. This defaults to all if not specified.
            :type ports: list of integers

            :param reverse: whether it is a reverse or forward power monitor query. This defaults to False if not specified, which means forward direction.
            :type reverse: bool

            :returns: the list of power for each specified or all ports.
            :rtype: list of tuples
        """
        tl1_cmd = 'rtrv-port-%spower::%s:%d:;\n' % (_tl1._reverse(reverse), _tl1._list(ports), _tl1._ctag)
        logger.info(tl1_cmd)
        self.session.socket.sendall(tl1_cmd)
        powerList = []
        for line in self._splitlines():
            port, power = line.split(_tl1._portsep)
            powerList.append((int(port.strip()[1:]), float(power[:-1])))
        return powerList

    def setAlarmThreshold(self, ports, alarmType=None, mode=None, edge=None, high=None, low=None, reverse=False):
        """
            This function sets the alarm parameters for the ports specified in
            the desired direction. The named parameters are all optional, but
            at least one parameter must be given.

            :param ports: the list of ports to set the alarm threshold for.
            :type ports: list of integers

            :param alarmType: This can be *LOS* (Loss of Service) or *DEGRADED*.  This defaults to *LOS* if not specified. If it is *DEGRADED*, the edge parameter must be omitted since the value will be fixed low. The low parameter is then used to set the threshold at which the degraded signal alarm fires. The high parameter must also be omitted since it is not relevant.
            :type alarmType: enum

            :param mode: This can be off, single or cont.
            :type mode: enum

            :param edge: This can be low or high.
            :type edge: enum

            :param high: The high alarm threshold level.
            :type high: float

            :param low: The low alarm threshold level.
            :type low: float

            :returns: None
            :rtype: None

            See also :meth:`alarmThreshold`.
        """
        if not any([alarmType, mode, edge, high, low]):
            raise ValueError("At least one of the arguments has to be provided: wavelength, offset or averaging time")
        data = ''
        separator=''
        for var, keyword in (alarmType, 'type'), (mode, 'mode'):
            if var:
                data += '%s%s=%s' % (separator, keyword, var)
                separator=_tl1._valsep
        for var, keyword in (low, 'low'), (high, 'high'):
            if var:
                data += '%s%s=%s' % (separator, keyword, var if var >= 0 else '(%s)' % var)
                separator=_tl1._valsep
        tl1_cmd = 'set-th-%spmon::%s:%d:::%s;\n' % (_tl1._reverse(reverse), _tl1._list(ports), _tl1._ctag, data)
        logger.info(tl1_cmd)
        self.session.socket.sendall(tl1_cmd)
        self._check_error()

    def alarmThreshold(self, ports=None, alarmType=None, reverse=False):
        """
            This function retrieves the threshold for the signal alarms for the
            desired ports and alarm type in the specified direction.

            :param ports: the list of ports to query the alarm threshold for. It defaults to all ports in the specified direction.
            :type ports: list of integers

            :param alarmType: This can be *LOS* (Loss of Service) or *DEGRADE default is *LOS*. This defaults to *LOS* if not specified.
            :type alarmType: enum

            :param reverse: this parameter determines whether a forward or reverse query is sent.
            :type reverse: bool

            :returns: the list of alarm threshold values (mode, edge, high and low) for each port requested. If it is degraded, the high value is *None* since it is not relevant.
            :rtype: list of tuples

            See also :meth:`setAlarmThreshold`.
        """
        tl1_cmd = 'rtrv-th-%spmon::%s:%d:%s;\n' % (_tl1._reverse(reverse), _tl1._list(ports), _tl1._ctag, _tl1._alarm_type(alarmType))
        logger.info(tl1_cmd)
        self.session.socket.sendall(tl1_cmd)
        alarmThresholdList = []
        for line in self._splitlines():
            port, data = line.split(_tl1._portsep)
            mode, edge, high, low = data.split(_tl1._valsep)
            alarmThresholdList.append((int(port.strip()[1:]), mode, edge, None if alarmType == 'DEGRADED' else float(high), float(low[:-1])))
        return alarmThresholdList

    def alarmState(self, ports=None, alarmType=None, reverse=False):
        """
            This function allows the state of the power monitor alarms to be
            queried in the specified direction. The state can be one or more of
            the following values:

            OFF
                The alarm is switched off.

            SINGLE
                The alarm is armed in single-shot mode.

            CONT
                The alarm is armed in continuous mode.

            TRIGGERED
                The alarm has been triggered.

            These values may be combined. For example, if a continuous-mode
            alarm has fired then the alarm state will be CONT *and* TRIGGERED.

            :param ports: the list of ports to query the alarm state for. It defaults to all ports in the specified direction if not specified.
            :type ports: list of integers

            :param alarmType: This can be LOS (Loss of Service) or DEGRADED. If it is not provided, the default is LOS.
            :type alarmType: enum

            :param reverse: this parameter determines whether a forward or reverse query is sent.
            :type reverse: bool

            :returns: the list of alarm state data for each port
            :rtype: list of tuples

            See also :meth:`clearAlarmState`.
        """
        tl1_cmd = 'rtrv-state-%spmon::%s:%d:%s;\n' % (_tl1._reverse(reverse), _tl1._list(ports), _tl1._ctag, _tl1._alarm_type(alarmType))
        logger.info(tl1_cmd)
        self.session.socket.sendall(tl1_cmd)
        alarmStateList = []
        for line in self._splitlines():
            # TODO: Once TL1 supports more than just mode name, extend this
            port, data = line.split(_tl1._portsep)
            alarmStateList.append((int(port.strip()[1:]), data[:-1]))
        return alarmStateList


    def clearAlarmState(self, ports=None, alarmType=None, reverse=False):
        """
            This function allows the state of the power monitor alarms to be
            reset in the specified direction for the alarm type and ports
            specified.

            :param ports: the list of ports to clean the alarm state for.  It defaults to all ports in the specified direction if not specified.
            :type ports: list of integers

            :param reverse: this parameter determines whether a forward or reverse clean is being executed.
            :type reverse: bool

            :param alarmType: This can be *LOS* (Loss of Service) or *DEGRADED*. This defaults to *LOS* if not specified.
            :type alarmType: enum

            :returns: None
            :rtype: None

            See also :meth:`alarmState`.
        """
        tl1_cmd = 'set-state-%s;\n' % _tl1._reversePortsCtagAlarmType(reverse, ports, alarmType)
        logger.info(tl1_cmd)
        self.session.socket.sendall(tl1_cmd)
        self._check_error()
