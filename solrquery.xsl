<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:h="http://apache.org/cocoon/request/2.0" xmlns:url="http://xml.apache.org/xalan/java/java.net.URLEncoder" exclude-result-prefixes="h url" extension-element-prefixes="url">
	<xsl:output method="xml" indent="yes"/>
	<!-- base url for solr queries -->
	<xsl:param name="solr"/>
	<!-- id of query in solrqueries.xml -->
	<xsl:param name="queryID">main</xsl:param>
	<!-- path to solrqueries.xml -->
	<xsl:param name="solrquery">../solrqueries.xml</xsl:param>
	
	<!-- query definition from solrqueries.xml -->
	<xsl:variable name="query" select="document($solrquery)/solr/query[@id = $queryID]"/>
	<!-- all request parameters -->
	<xsl:variable name="request_parameters" select="/h:request/h:requestParameters/h:parameter"/>
	<!-- "field" request parameters -->
	<xsl:variable name="request_fields" select="$request_parameters[@name='field']/h:value"/>
	<!-- "q" request parameters -->
	<xsl:variable name="request_terms" select="$request_parameters[@name='q']/h:value"/>
	<!-- "operator" request parameters -->
	<xsl:variable name="request_operators" select="$request_parameters[@name='operator']/h:value"/>
	<!-- "qq" request parameter: pre-composed query -->
	<xsl:variable name="qq" select="$request_parameters[@name = 'qq']/h:value"/>
	<xsl:template name="q">
		<!-- "q" parameters contain search terms from a form; each should be accompanied by a "field" parameter
		containing the name of the field within which that term is to be searched. The "field" parameter is optional, 
		however, and if it is blank or absent no field prefix will be attached to the search term in the Solr URL. 
		"operator" parameters contain boolean operators to be inserted between search terms.
	
		Output: the value of the q parameter in the Solr URL, i.e. a query in Lucene syntax
		-->
		<xsl:variable name="q">
			<xsl:for-each select="$request_terms">
				<!-- loop through "q" parameters -->
				<xsl:if test=". != ''">
					<!-- number of this "q" parameter in sequence - used to find matching "field" and "operator" parameters -->
					<xsl:variable name="num" select="position()"/>
					<!-- matching "field" parameter -->
					<xsl:variable name="request_field" select="$request_fields[$num]"/>
					<!-- is this a permitted field? Note use of equality statement in form string = nodeset: true if there is a node 
				in that nodeset that matches the value of the string -->
					<xsl:choose>
						<xsl:when test="$request_field = $query/fields/field">
							<!-- matching operator; note that operator[1] matches q[2] etc., since no operator is required before the 
						first term -->
							<xsl:variable name="request_operator">
								<xsl:if test="$num &gt; 1">
									<xsl:value-of select="$request_operators[$num - 1]"/>
								</xsl:if>
							</xsl:variable>
							<!-- insert space if needed -->
							<xsl:if test="$num &gt; 1">
								<xsl:text> </xsl:text>
							</xsl:if>
							<!-- handle operator -->
							<xsl:choose>
								<xsl:when test="not(preceding-sibling::* != '')">
									<!-- i.e. there is no non-blank preceding term, so no operator is necessary -->
									<xsl:text/>
								</xsl:when>
								<xsl:when test="$request_operator != ''">
									<xsl:value-of select="$request_operator"/>
									<xsl:text> </xsl:text>
								</xsl:when>
								<xsl:otherwise>
									<!-- default operator -->
									<xsl:text>AND </xsl:text>
								</xsl:otherwise>
							</xsl:choose>
							<!-- handle field name -->
							<xsl:if test="$request_field != ''">
								<xsl:value-of select="$request_field"/>
								<xsl:text>:</xsl:text>
							</xsl:if>
							<!-- finally, current search term, in brackets to make subsequent parsing of the query easier -->
							<xsl:text>(</xsl:text>
							<xsl:value-of select="."/>
							<xsl:text>)</xsl:text>
						</xsl:when>
						<xsl:otherwise>
							<xsl:message terminate="yes">"<xsl:value-of select="$request_field"/>"
								is not a permitted query field in query "<xsl:value-of
									select="$queryID"/>".</xsl:message>
						</xsl:otherwise>
					</xsl:choose>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:choose>
			<xsl:when test="normalize-space($q) != '' or $qq != ''">
				<xsl:value-of select="$q"/>
			</xsl:when>
			<xsl:otherwise>
				<xsl:text>*:*</xsl:text>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<!-- 
		Handle application parameters from the query definition 
		Output: query string fragment; this fragment is intended to be first in the URL, so the first
			element does not have a preceding ampersand
	-->
	<xsl:template name="application">
		<xsl:for-each select="$query/application/parameter">
			<xsl:if test="position() != 1">
				<xsl:text>&amp;</xsl:text>
			</xsl:if>
			<xsl:value-of select="@name"/>
			<xsl:text>=</xsl:text>
			<xsl:value-of select="url:encode(., 'UTF-8')"/>
		</xsl:for-each>
	</xsl:template>
	<!--

		Handle facet parameters from the query definition

	-->
	<xsl:template name="facets">
		<!-- if there's a facet.field or facet.query value in input and facets are allowed, add facets provided their fields are permitted; 
		otherwise use all permitted fields -->
		<xsl:if test="$query/facets">
			<xsl:variable name="request_facets" select="$request_parameters[@name='facet.field' or @name='facet.query']"/>
			<xsl:text>&amp;facet=true</xsl:text>
			<!-- copy all facet attributes to Solr URL -->
			<xsl:for-each select="$query/facets/@*[starts-with(name(), 'attr_')]">
				<xsl:text>&amp;facet.</xsl:text>
				<xsl:value-of select="substring-after(name(), 'attr_')"/>
				<xsl:text>=</xsl:text>
				<xsl:value-of select="url:encode(., 'UTF-8')"/>
			</xsl:for-each>
			<!-- add facet fields from query definition that are specified in request parameters; if none are specified in request parameters, add all  -->
			<xsl:for-each select="$query/facets/field[. = $request_facets or (count($request_facets) = 0)]">
				<xsl:text>&amp;facet.field=</xsl:text>
				<xsl:value-of select="url:encode(., 'UTF-8')"/>
				<!-- handle field-level attributes -->
				<xsl:for-each select="@*[starts-with(name(), 'attr_')]">
					<xsl:text>&amp;f.</xsl:text>
					<xsl:value-of select=".."/>
					<xsl:text>.facet.</xsl:text>
					<xsl:value-of select="substring-after(name(), 'attr_')"/>
					<xsl:text>=</xsl:text>
					<xsl:value-of select="url:encode(., 'UTF-8')"/>
				</xsl:for-each>
			</xsl:for-each>
			<!-- likewise handle facet queries -->
			<xsl:for-each select="$query/facets/query[. = $request_facets or (count($request_facets) = 0)]">
				<xsl:text>&amp;facet.query=</xsl:text>
				<xsl:value-of select="url:encode(., 'UTF-8')"/>
			</xsl:for-each>
		    <!-- and facet ranges -->
		        <!-- if there is no existing fq for this field, use range with no @breakdown-from; if there is, find
		            the range using the @breakdown-from that matches the fq -->
         <xsl:for-each select="$query/facets/hierarchy[@type='date'][@fname = $request_facets or (count($request_facets) = 0)]">
            <xsl:variable name="fname" select="@fname"/>
            <xsl:variable name="rangeprefix">
               <xsl:text>&amp;f.</xsl:text>
               <xsl:value-of select="$fname"/>
               <xsl:text>.facet.range.</xsl:text>
            </xsl:variable>
 
            <!-- collect information about current level, represented by the fq -->
            <xsl:variable name="fq" select="$request_parameters[@name='fq']/h:value[starts-with(., concat($fname, ':'))]"/>
            <xsl:variable name="fq-term" select="translate(substring-after($fq, ':'), '[]', '')"/>
            <xsl:variable name="fq-start" select="substring-before(substring-before($fq-term, ' '), '/')"/>
            <xsl:variable name="fq-end" select="substring-before(substring-after($fq-term, ' TO '), '/')"/>
            
            <xsl:variable name="fq-gap">
               <xsl:choose>
                  <xsl:when test="contains($fq-term, '-1DAY')">
                     <xsl:value-of select="concat('+', substring-before(substring-after(substring-after($fq-term, ' TO '), '+'), '-1DAY'))"/>
                  </xsl:when>
                  <xsl:when test="$fq-term != ''">
                     <xsl:value-of select="concat('+', substring-after(substring-after($fq-term, ' TO '), '+'))"/>
                  </xsl:when>
               </xsl:choose>
            </xsl:variable> 

            <!-- identify the level to be used for the new query -->
            <xsl:variable name="new-range"
               select="range[
		          (not($fq) and not(@breakdown-from))
		          or
		          ($fq and (@breakdown-from = $fq-gap))
		          ]"/>

            <!-- select start and end dates -->
            <xsl:variable name="start">
               <xsl:choose>
                  <xsl:when test="$fq">
                     <xsl:value-of select="$fq-start"/>
                  </xsl:when>
                  <xsl:otherwise>
                     <xsl:value-of select="$new-range/@start"/>
                  </xsl:otherwise>
               </xsl:choose>
               <xsl:text>/</xsl:text>
               <xsl:value-of select="$new-range/@gap-unit"/>
            </xsl:variable>
            <xsl:variable name="end">
               <xsl:choose>
                  <xsl:when test="$fq">
                     <xsl:value-of select="$fq-end"/>
                  </xsl:when>
                  <xsl:otherwise>
                     <xsl:value-of select="$new-range/@end"/>
                  </xsl:otherwise>
               </xsl:choose>
               <xsl:text>/</xsl:text>
               <xsl:value-of select="$new-range/@gap-unit"/>
               <xsl:value-of select="$fq-gap"/>
            </xsl:variable>

            <xsl:comment>fq-gap: <xsl:value-of select="$fq-gap"/>; @breakdown-from: <xsl:value-of select="@breakdown-from"/> fq-start: {<xsl:value-of
                  select="$fq-start"/>}; fq-end: {<xsl:value-of select="$fq-end"/>} </xsl:comment>
            <xsl:comment><xsl:value-of select="concat(@gap-operator, @gap-quantum, @gap-unit)"/>: fq=<xsl:value-of select="count($fq)"/></xsl:comment>
            <!-- TODO make this work for non-date ranges. This assumes the fq is like this:
                      date:[1901-01-01T12:00:00Z TO 1901-01-01T12:00:00Z+5YEAR]  
                    -->
            
            <xsl:text>&amp;facet.range=</xsl:text>
            <xsl:value-of select="url:encode($fname, 'UTF-8')"/>

            <xsl:value-of select="$rangeprefix"/>
            <xsl:text>start=</xsl:text>
            <xsl:value-of select="url:encode($start, 'UTF-8')"/>
            

            <xsl:value-of select="$rangeprefix"/>
            <xsl:text>end=</xsl:text>
            <xsl:value-of select="url:encode($end, 'UTF-8')"/>

            <xsl:value-of select="$rangeprefix"/>
            <xsl:text>gap=</xsl:text>
            <xsl:value-of select="url:encode(concat($new-range/@gap-operator, $new-range/@gap-quantum, $new-range/@gap-unit), 'UTF-8')"/>
         </xsl:for-each>
		   
		   <xsl:for-each select="$query/facets/hierarchy[@type='multifield'][@name = $request_facets or (count($request_facets) = 0)]">
		      <!-- find the config that governs the current facets -->
		      <xsl:apply-templates select="*[1]" mode="multifield"/>
		   </xsl:for-each>
		      
		</xsl:if>
	</xsl:template>

   <xsl:template match="range" mode="multifield">
      <xsl:param name="force">false</xsl:param>
      <!-- for now we assume a range can only be the first config within a multifield hierarchy, and will only be triggered by a force -->
      
      <!-- diagnostic -->
      <!--
      <xsl:text>&amp;config=</xsl:text>
      <xsl:value-of select="name()"/>
      <xsl:text>/</xsl:text>
      <xsl:value-of select="@fname"/>
      -->
      
      <xsl:choose>
         <xsl:when test="$force='true'">
            <!-- this is the one, so add it to the solr query 
            
            <range fname="date_y" start="1876" end="1920" gap-operator="+" gap-quantum="5"/>

            facet.range=date_y
            &f.date_y.facet.range.start=1800
            &f.date_y.facet.range.end=2000
            &f.date_y.facet.range.gap=5
		     -->
            
            <xsl:variable name="rangeprefix">
               <xsl:text>f.</xsl:text>
               <xsl:value-of select="@fname"/>
               <xsl:text>.facet.range.</xsl:text>
            </xsl:variable>
            
            <xsl:text>&amp;c_multifield=</xsl:text>
            <xsl:value-of select="url:encode(concat(../@name, ':', 'range:', @fname), 'UTF-8')"/>
            
            <xsl:text>&amp;facet.range=</xsl:text>
            <xsl:value-of select="url:encode(@fname, 'UTF-8')"/>

            <xsl:text>&amp;</xsl:text>
            <xsl:value-of select="$rangeprefix"/>
            <xsl:text>start=</xsl:text>
            <xsl:value-of select="url:encode(@start, 'UTF-8')"/>

            <xsl:text>&amp;</xsl:text>
            <xsl:value-of select="$rangeprefix"/>
            <xsl:text>end=</xsl:text>
            <xsl:value-of select="url:encode(@end, 'UTF-8')"/>

            <xsl:text>&amp;</xsl:text>
            <xsl:value-of select="$rangeprefix"/>
            <xsl:text>gap=</xsl:text>
            <xsl:value-of select="url:encode(@gap, 'UTF-8')"/>
         </xsl:when>
         <xsl:otherwise>
            <xsl:apply-templates select="following-sibling::*[1]" mode="multifield"/>
         </xsl:otherwise>
      </xsl:choose>
      
   </xsl:template>
   
   <xsl:template match="field" mode="multifield">
      <xsl:param name="force">false</xsl:param>
      
      <xsl:variable name="breakdown-from" select="@breakdown-from"/>
      
      <!-- look for fq for this breakdown -->
      <xsl:variable name="fq" select="$request_parameters[@name='fq']/h:value[starts-with(., concat($breakdown-from, ':'))]"/>
      <xsl:variable name="fq-term" select="translate(substring-after($fq, ':'), '[]', '')"/>
      <xsl:variable name="fq-type">
         <xsl:choose>
            <xsl:when test="contains($fq-term, ' TO ')">range</xsl:when>
            <xsl:otherwise>field</xsl:otherwise>
         </xsl:choose>
      </xsl:variable>
      
      <!-- diagnostic -->
  <!--    <xsl:text>&amp;config=</xsl:text>
      <xsl:value-of select="name()"/>
      <xsl:text>/</xsl:text>
      <xsl:value-of select="@fname"/>
      <xsl:text>/</xsl:text>
      <xsl:value-of select="$fq-term"/>-->
      
      <xsl:choose>
         <xsl:when test="(@breakdown-type='range' and $fq-type='range') or (@breakdown-type='field' and $fq-term != '') or ($force='true')">
            <!-- this is the one, so add it to the solr query -->

            <xsl:text>&amp;c_multifield=</xsl:text>
            <xsl:value-of select="url:encode(concat(../@name, ':', 'field:', @fname), 'UTF-8')"/>
            
            <xsl:text>&amp;facet.field=</xsl:text>
            <xsl:value-of select="url:encode(@fname, 'UTF-8')"/>
             
         </xsl:when>
         <xsl:otherwise>
            <!-- continue down the line; if there are no more, force the first config (since this must be an initial search) -->
            <xsl:choose>
               <xsl:when test="following-sibling::*">
                  <xsl:apply-templates select="following-sibling::*[1]" mode="multifield"/>
               </xsl:when>
               <xsl:otherwise>
                  <xsl:apply-templates select="../*[1]" mode="multifield">
                     <xsl:with-param name="force">true</xsl:with-param>
                  </xsl:apply-templates>
               </xsl:otherwise>
            </xsl:choose>
         </xsl:otherwise>
      </xsl:choose>
   </xsl:template>
   <!--

		Handle parameters from the query definition
		It is assumed that a single value for each parameter may be present in the request parameters.
	-->
	<xsl:template name="parameters">
		<xsl:if test="$query/parameters">
			<xsl:for-each select="$query/parameters/parameter">
				<!-- loop through parameters in query definition -->
				<xsl:variable name="name" select="@name"/>
				<!-- corresponding request parameter -->
				<xsl:variable name="param" select="$request_parameters[@name = $name]"/>
				<xsl:text>&amp;</xsl:text>
				<xsl:value-of select="$name"/>
				<xsl:text>=</xsl:text>
				<!-- parameters have three types: enumerated (default), integer, string -->
				<xsl:choose>
					<xsl:when test="@type = 'integer'">
						<xsl:choose>
							<!-- if we have an acceptable integer, use it: it must contain nothing but digits, and 
								be >= @min and <= @max -->
							<xsl:when test="$param != '' and translate($param, '0123456789', '') = ''
								and (not(@min) or (number($param) &gt;= number(@min)))
								and (not(@max) or (number($param) &lt;= number(@max)))
							">
								<xsl:value-of select="$param"/>
							</xsl:when>
							<!-- otherwise use default -->
							<xsl:otherwise>
								<xsl:value-of select="value[@default='true']"/>
							</xsl:otherwise>
						</xsl:choose>
					</xsl:when>
					<xsl:when test="@type = 'string'">
						<!-- string can have any value, including blank -->
						<xsl:value-of select="url:encode($param, 'UTF-8')"/>
					</xsl:when>
					<xsl:when test="$param = value">
						<!-- enumerated type: if the input value is in the list of permitted values, use it.
						Note use of equality statement between string and nodeset: true if nodeset contains a 
						value that matches the string -->
						<xsl:value-of select="url:encode($param, 'UTF-8')"/>
					</xsl:when>
					<xsl:otherwise>
						<!-- otherwise use default value -->
						<xsl:value-of select="url:encode(value[@default='true'], 'UTF-8')"/>
					</xsl:otherwise>
				</xsl:choose>
			</xsl:for-each>
		</xsl:if>
	</xsl:template>
	<!--

		Handle filter queries
		Add fq elements to Solr URL from request parameters, provided the fields are permitted

	-->
	<xsl:template name="filters">
		<xsl:if test="$query/filters">
			<xsl:for-each select="$request_parameters[@name='fq']/h:value">
				<xsl:if test="contains(., ':')">
					<xsl:variable name="name" select="substring-before(., ':')"/>
					<xsl:choose>
						<xsl:when test="$name = $query/filters/filter">
						<xsl:text>&amp;fq=</xsl:text>
						<xsl:value-of select="url:encode(., 'UTF-8')"/>
					</xsl:when>
					<xsl:otherwise>
						<xsl:message terminate="yes">"<xsl:value-of select="$name"/>" is not a permitted filter query field in query "<xsl:value-of select="$queryID"/>"</xsl:message>
					</xsl:otherwise>
					</xsl:choose>
				</xsl:if>
			</xsl:for-each>
		</xsl:if>
	</xsl:template>
	<!--

		Handle highlighting
		Similar to facets: add permitted elements to Solr URL, copying attributes as well

	-->
	<xsl:template name="highlighting">
		<xsl:if test="$query/highlighting">
			<xsl:text>&amp;hl=true</xsl:text>
			<xsl:for-each select="$query/highlighting/@*[starts-with(name(), 'attr_')]">
				<xsl:text>&amp;hl.</xsl:text>
				<xsl:value-of select="substring-after(name(), 'attr_')"/>
				<xsl:text>=</xsl:text>
				<xsl:value-of select="url:encode(., 'UTF-8')"/>
			</xsl:for-each>
			<xsl:if test="$query/highlighting/field">
				<xsl:text>&amp;hl.fl=</xsl:text>
				<xsl:for-each select="$query/highlighting/field">
					<xsl:value-of select="url:encode(normalize-space(.), 'UTF-8')"/>
					<xsl:if test="position() != last()">
						<xsl:value-of select="url:encode(',', 'UTF-8')"/>
					</xsl:if>
				</xsl:for-each>
				<xsl:for-each select="$query/highlighting/field/@*[starts-with(name(), 'attr_')]">
					<xsl:text>&amp;f.</xsl:text>
					<xsl:value-of select=".."/>
					<xsl:text>.hl.</xsl:text>
					<xsl:value-of select="substring-after(name(), 'attr_')"/>
					<xsl:text>=</xsl:text>
					<xsl:value-of select="url:encode(., 'UTF-8')"/>
				</xsl:for-each>
			</xsl:if>
		</xsl:if>
	</xsl:template>
	
	<xsl:template name="applicationqueryterms">
	    <!-- handle any additions to the query from the application section of the query definision (q_and etc.) -->
        <xsl:variable name="terms">
            <xsl:for-each select="$query/application/queryterm">
                <xsl:text> </xsl:text>
                <xsl:value-of select="@name"/>
                <xsl:text> </xsl:text>
                <xsl:value-of select="."/>
            </xsl:for-each>
        </xsl:variable>
	    <xsl:value-of select="url:encode($terms, 'UTF-8')"/>
	</xsl:template>
		<!--

		Main template
		
		-->
	<xsl:template match="/">
		<xsl:variable name="q">
			<xsl:call-template name="q"/>
		</xsl:variable>
		<xsl:variable name="solrUrl">
			<xsl:value-of select="$solr"/>
			<xsl:call-template name="application"/>
			<xsl:text>&amp;q=</xsl:text>
			<xsl:if test="$qq = '' and $q = ''">
				<xsl:value-of select="url:encode('*:*', 'UTF-8')"/>
			</xsl:if>
			<xsl:if test="$qq">
				<xsl:value-of select="url:encode($qq, 'UTF-8')"/>
			</xsl:if>
			<xsl:if test="($qq != '') and ($q != '')">
				<xsl:value-of select="url:encode(' AND ', 'UTF-8')"/>
			</xsl:if>
			<xsl:value-of select="url:encode($q, 'UTF-8')"/>
			<xsl:call-template name="applicationqueryterms"/>
			<xsl:call-template name="filters"/>
			<xsl:call-template name="facets"/>
			<xsl:call-template name="highlighting"/>
			<xsl:call-template name="parameters"/>
		</xsl:variable>
	    <wrapper solrUrl="{$solrUrl}">
	        <xsl:text>&#x0a;</xsl:text>
		<!-- build the CInclude statement that will pull in the Solr search results -->
		<cinclude:include src="include.xml" xmlns:cinclude="http://apache.org/cocoon/include/1.0">
			<xsl:attribute name="src">
				<xsl:value-of select="$solrUrl"/>
		</xsl:attribute>
		</cinclude:include>
		<!-- copy the query definition so we'll have it available when generating the html -->
		<xsl:copy-of select="$query"/>
		</wrapper>
	</xsl:template>
</xsl:stylesheet>
