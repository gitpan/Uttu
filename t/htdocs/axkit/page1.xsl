<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  version="1.0"
> 

  <xsl:output
    method="xhtml"
    indent="yes"
    doctype-public="-//W3C//DTD XHTML 1.0 Strict//EN"
    doctype-system="DTD/xhtml1-strict.dtd"
  />

  <xsl:template match="/">
    <xsl:apply-templates/>
  </xsl:template>

  <xsl:template match="doit">
This is an AxKit Page!
  </xsl:template>

</xsl:stylesheet>
