from time import strftime
import os.path
import logging
import socket
import _tl1
import sys
import json
import os


logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
ch = logging.StreamHandler()
ch.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
ch.setFormatter(formatter)
logger.addHandler(ch)

class CrossConnectionError(Exception):
    """
        Exception raised for errors during the cross connection interaction.
    """
    def __init__(self, message = None):
        """
            :param message: explanation of the error.
            :type message: string

            See also :class:`CrossConnection`.
        """
        #super(CrossConnectionError, self).__init__('Failed to use the Cross Connection functionality: {0}'.format(message))
        self.message = message

    def setMessage(self, message):
	self.message = message

class CrossConnection(object):

    def __init__(self, session):
        """
            Initializes a session object.

            :param session: the session object that represents the session under which the Optical Cross Connection (OXC) functionality is being used.
            :type session: Session

            :raises CrossConnectionError: if the cross connection functionality is not supported on the switch. This exception is also raised throughout the class in any method where there can be any issue.

            See also :class:`CrossConnectionError` and :class:`Session`.
        """
        self.session = session
        #print "self.session : ", self.session

    def _parseTl1Error(self, tl1Func):
	return tl1Func(self.session, CrossConnectionError())

    def _splitlines(self):
        return self._parseTl1Error(_tl1._splitlines)

    def _impexp_splitlines(self):
        return self._parseTl1Error(_tl1._impexp_splitlines)

    def _check_error(self):
        self._parseTl1Error(_tl1._check_error)

    def _impexp_check_error(self):
        self._parseTl1Error(_tl1._impexp_check_error)

    def setConnection(self, inputPorts, outputPorts, forced=False, opr=None):
        """
            :param inputPorts: these are the ingress ports.
            :type inputPorts: list of integers

            :param outputPorts: these are the egress ports.
            :type outputPorts: list of integers

            :param forced: boolean parameter defining whether APS should affect the outcome of the attempt. If it is forced, then the ports are always added.
            :type forced: bool

            :returns: None
            :rtype: None

            See also :meth:`removeConnection` and :meth:`connection`.
        """
        if opr == 'import':
            tl1_cmd = 'dlt-patch::all:%d:%s;\n' % (_tl1._ctag, ':frcd' if forced == True else '')
            #logger.info(tl1_cmd)
            self.session.sendall(tl1_cmd)
            self._impexp_check_error()
        else:
            pass
        tl1_cmd = 'ent-patch::%s,%s:%d:%s;\n' % (_tl1._list(inputPorts), _tl1._list(outputPorts), _tl1._ctag, ':frcd' if forced == True else '')
        self.session.sendall(tl1_cmd)
        if opr == 'import' or opr == 'export':
            try:
                self._impexp_check_error()
                logger.info("Import operation completed.")
            except Exception as err:
                logger.info("Import operation failed.")
        else:
            logger.info(tl1_cmd)
            self._check_error()

    def removeConnection(self, ports=None, forced=False, opr=None):
        """
            :param ports: the number of the ingress and egress ports. This defaults to the all connected ports if not specified.
            :type ports: list of integers

            :param forced: defines whether APS should affect the outcome of the attempt. If it is forced, then the ports are always deleted.
            :type forced: bool

            :returns: None
            :rtype: None

            See also :meth:`setConnection` and :meth:`connection`.
        """
        tl1_cmd = 'dlt-patch::%s:%d:%s;\n' % (_tl1._list(ports), _tl1._ctag, ':frcd' if forced == True else '')
        self.session.sendall(tl1_cmd)
        if opr == 'import' or opr == 'export':
            self._impexp_check_error()
        else:
            logger.info(tl1_cmd)
            self._check_error()

#-------------------------------------------------------------------------------
# THL input:    06.Dez 2019

    def setShutter(self, ports=None, interv=None, forced=False, opr=None):
        """
            :param ports: the number of the ingress and egress ports. This defaults to the all connected ports if not specified.
            :type ports: list of integers

            :interv:  offintv,onintvl,cycles -  eg: 10000,300,1

            :param forced: defines whether APS should affect the outcome of the attempt. If it is forced, then the ports are always deleted.
            :type forced: bool

            :returns: None
            :rtype: None

            See also :meth:`setConnection` and :meth:`connection`.
        """
        tl1_cmd = 'ent-port-flap::%s:%d::%s:%s;\n' % (_tl1._list(ports), _tl1._ctag, _tl1._list(interv), ':frcd' if forced == True else '')
        self.session.sendall(tl1_cmd)
        if opr == 'import' or opr == 'export':
            self._impexp_check_error()
        else:
            logger.info(tl1_cmd)
            self._check_error()


#-------------------------------------------------------------------------------
# THL input:    11.Dez 2019

    def queryShutter(self, ports=None, forced=False, opr=None):
        """
            :param ports: the number of the ingress and egress ports. This defaults to the all connected ports if not specified.
            :type ports: list of integers

            :param forced: defines whether APS should affect the outcome of the attempt. If it is forced, then the ports are always deleted.
            :type forced: bool

            :returns: None
            :rtype: None

            See also :meth:`setConnection` and :meth:`connection`.
        """
        tl1_cmd = 'rtrv-port-flap::%s:%d::%s;\n' % (_tl1._list(ports), _tl1._ctag, ':frcd' if forced == True else '')
        self.session.sendall(tl1_cmd)
        if opr == 'import' or opr == 'export':
            self._impexp_check_error()
        else:
            logger.info(tl1_cmd)
            self._check_error()

#-------------------------------------------------------------------------------

    def connection(self, inputPorts=None, opr=None):
        """
            Returns all the cross connections corresponding to the input ports
            specified.

            :param inputPorts: The number of the ingress ports. This defaults to the all connected input ports if not specified.
            :type inputPorts: list of integers

            :returns: the connection list.
            :rtype: list of ingress, egress tuples

            See also :meth:`setConnection` and :meth:`removeConnection`.
        """
        tl1_cmd = 'rtrv-patch::%s:%d:;\n' % (_tl1._list(inputPorts), _tl1._ctag)
        self.session.sendall(tl1_cmd)
        if opr == 'import' or opr == 'export':
            self._impexp_check_error()
        else:
            logger.info(tl1_cmd)
            #self._check_error()

        connectionList = []
        for line in self._splitlines():
	    if line:
		ingress, egress = line.split(_tl1._valsep)
		connectionList.append((int(ingress.strip()[1:]), int(egress[:-1])))
        #return connectionList

    def export_connection(self, filename, opr=None):
        """
            Export current state of the cross connections

            :param filename: any name.
            :type filename: string.
        """
        tl1_cmd = 'rtrv-patch:::%d:;\n' % (_tl1._ctag)
        self.session.sendall(tl1_cmd)
        logger.info("Exporting the current connection state in a file...")

        key = 'portconns'
        connectionDict = {}

        for line in self._impexp_splitlines():
            connectionDict.setdefault(key, [])
            c = line[4:-1]
            out =  c.split(',')
            connectionDict[key].append(out)
        j =  json.dumps(connectionDict , ensure_ascii=False)
        obj = json.loads(j)
        json_output =  json.dumps(obj,sort_keys=True, indent=4)
        #filename  = filename+ '_' + strftime("%Y-%m-%dT%H-%M-%S") +'.json'
        filename  = filename +'.json'
        f_open = open(filename, 'wb')
        f_open.write(json_output)
        f_open.close
        logger.info("Export operation completed.")


    def import_connection(self, filename):
        """
            Read json file and create cross connections based on that.

            :param filename: file with json extension.
            :type filename: string.
        """
        if os.path.isfile(filename):
            pass
        else:
            logger.error('File doesn\'t exist.\n')
            exit(1)
        if '.json' in filename:
            pass
        else:
            logger.error('Not a json file.Enter a valid file with json extension.\n')
            exit(1)
        f_open = open(filename).read()
        ingrlst = []
        egrlst = []
        l1 = []
        try:
            python_obj = json.loads(f_open)
            conn_list = python_obj.values()
            if os.path.getsize(filename) == 0:
               logger.error("File is empty. Make sure the exported file has some connections.")
               exit(1)
            elif len(conn_list) == 0:
                logger.error("File is empty. Make sure the exported file has some connections.")
                exit(1)
            else:
                for index in range(0,len(conn_list)):
                    conn_list_1 = python_obj.values()[index]
                    for ind in range(0,len(conn_list_1)):
                        ingrlst.append(str(python_obj.values()[index][ind][0]))
                        egrlst.append(str(python_obj.values()[index][ind][1]))
                self.setConnection(ingrlst, egrlst, opr = 'import')
        except ValueError, e:
            logger.error('Not a valid file.Import operation failed.')
            exit(1)
