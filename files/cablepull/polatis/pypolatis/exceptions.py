class PolatisError(Exception):
    """ 
        All polatis exceptions are derived from this class.
    """
    def __init__(self, message):
        """ 
            :param message: explanation of the error.
            :type message: string

            See also :class:`PolatisError`.
        """
        super(PolatisError, self).__init__('PolatisError: {0}'.format(message))
        self.message = message
