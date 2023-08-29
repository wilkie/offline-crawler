USERNAME='wilkie@code.org'
PASSWORD='mypassword'

# You can specify things based on domain, here
if [[ ${DOMAIN_PREFIX} == "levelbuilder" ]]; then
    USERNAME='wilkie+levelbuilder@code.org'
    PASSWORD='mylevelbuilderpassword'
fi
