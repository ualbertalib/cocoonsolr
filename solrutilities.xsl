<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:url="http://xml.apache.org/xalan/java/java.net.URLEncoder"
   xmlns:exsl="http://exslt.org/common" exclude-result-prefixes="url exsl calendar" extension-element-prefixes="url exsl"
   xmlns:calendar="http://apache.org/cocoon/calendar/1.0">
   <!-- path to the query result page, to which queries are posted -->
   <xsl:param name="result-page">result.html</xsl:param>
   <!-- cocoonsolr query configuration -->
   <xsl:variable name="solr_query_config" select="/wrapper/query"/>
   <!--	<xsl:variable name="solr_query_config" select="/solr/query[@id='main']"/>-->
   <xsl:variable name="solr_query_config_fields" select="$solr_query_config/fields/field"/>
   <xsl:variable name="solr_query_config_sorts" select="$solr_query_config/parameters/parameter[@name='sort']/value"/>
   <!-- generate the list of facet configurations, copying labels as necessary -->
   <xsl:variable name="solr_query_config_facets_raw">
      <facets>
         <xsl:copy-of select="$solr_query_config/facets/@*"/>
         <xsl:for-each select="$solr_query_config/facets/*">
            <xsl:copy>
               <xsl:if test="name() = 'query'">
                  <xsl:copy-of select="../query[@id = current()/@id][1]/@*[name() = 'group' or name() = 'label']"/>
               </xsl:if>
               <xsl:copy-of select="@*"/>
               <xsl:copy-of select="range | field"/>
               <xsl:value-of select="."/>
            </xsl:copy>
         </xsl:for-each>
      </facets>
   </xsl:variable>
   <!-- convert the generated list to a nodeset so it can searched -->
   <xsl:variable name="solr_query_config_facets" select="exsl:node-set($solr_query_config_facets_raw)/facets"/>
   <xsl:variable name="solr_query_config_filters" select="$solr_query_config/filters/filter"/>
   <!-- solr response -->
   <xsl:variable name="solr_response" select="/wrapper/response"/>
   <!-- all parameters -->
   <xsl:variable name="solr_params" select="$solr_response/lst[@name = 'responseHeader']/lst[@name='params']"/>
   <xsl:variable name="solr_sort" select="$solr_params/str[@name='sort']"/>
   <xsl:variable name="solr_q" select="$solr_params/str[@name='q']"/>
   <xsl:variable name="solr_facet_fields" select="$solr_response/lst[@name='facet_counts']/lst[@name='facet_fields']"/>
   <xsl:variable name="solr_facet_queries" select="$solr_response/lst[@name='facet_counts']/lst[@name='facet_queries']"/>
   <xsl:variable name="solr_facet_ranges" select="$solr_response/lst[@name='facet_counts']/lst[@name='facet_ranges']"/>
   <!-- all fq parameters -->
   <xsl:variable name="solr_fq_raw" select="$solr_params/str[@name='fq'] 
        | 
        $solr_params/arr[@name='fq']/str"/>
   <!-- strip fqs that are application parameters -->
   <xsl:variable name="solr_fq" select="$solr_fq_raw[not(. = $solr_query_config/application/parameter[@name='fq'])]"/>
   <!-- highlighting snippets -->
   <xsl:variable name="solr_highlighting" select="$solr_response/lst[@name='highlighting']/lst"/>
   <xsl:variable name="solr_url" select="/wrapper/@solrUrl"/>
   <!-- query url that reproduces the current query, but without sort, filters or navigational elements -->
   <xsl:variable name="solr_baseurl">
      <xsl:value-of select="$result-page"/>
      <xsl:text>?qq=</xsl:text>
      <xsl:value-of select="url:encode($solr_q, 'UTF-8')"/>
   </xsl:variable>
   <!-- current query including sort and filters, for use in navigation links -->
   <!-- exclude application parameters from query since they will be re-added when the query is submitted -->
   <xsl:variable name="solr_queryurl">
      <xsl:value-of select="$solr_baseurl"/>
      <xsl:for-each select="$solr_fq">
         <xsl:text>&amp;fq=</xsl:text>
         <xsl:value-of select="url:encode(., 'UTF-8')"/>
      </xsl:for-each>
      <xsl:text>&amp;sort=</xsl:text>
      <xsl:value-of select="url:encode($solr_sort, 'UTF-8')"/>
   </xsl:variable>
   <xsl:variable name="solr_rows" select="$solr_params/str[@name='rows']"/>
   <xsl:variable name="solr_numfound" select="$solr_response/result/@numFound"/>
   <xsl:variable name="solr_start" select="$solr_response/result/@start"/>
   <!-- note: start should always be evenly divisible by rows -->
   <xsl:variable name="solr_curpage" select="$solr_start div $solr_rows + 1"/>
   <xsl:variable name="solr_lastpage" select="ceiling($solr_numfound div $solr_rows)"/>
   <!-- ***************************************************************************

Hidden fields, for inclusion in search forms
	$solr_base_hidden reproduces the current query, but without sort, filters or navigation
	$solr_base_hidden_fq contains the fq filters
	TODO: add sort, navigation - if they turn out to be necessary for anything

******************************************************************************** -->
   <xsl:variable name="solr_base_hidden">
      <!-- hidden fields that reproduce the current query, but without sort, filters or navigational elements -->
      <input type="hidden" name="qq" value="{$solr_q}"/>
   </xsl:variable>
   <xsl:variable name="solr_base_hidden_fq">
      <!-- hidden fields with current filters  -->
      <xsl:for-each select="$solr_fq">
         <input type="hidden" name="fq" value="{.}"/>
      </xsl:for-each>
   </xsl:variable>
   <!-- ***************************************************************************

	Public Templates 

******************************************************************************** -->
   <!--
solr_broader_search: 	generates url for broader query, for a given field and term - so don't carry over any of the original query 
	- used for wrapping doc elements with queries to start a new search for that element
	e.g. a search for all items by the author of this item

Example of use - applied to arr/str:

			<a>
				<xsl:attribute name="href">
					<xsl:call-template name="solr_broader_search">
						<xsl:with-param name="field" select="../@name"/>
						<xsl:with-param name="term" select="."/>
					</xsl:call-template>
				</xsl:attribute>
				<xsl:value-of select="."/>
			</a>

-->
   <xsl:template name="solr_broader_search">
      <xsl:param name="field"/>
      <xsl:param name="term"/>
      <xsl:text>?field=</xsl:text>
      <xsl:value-of select="url:encode($field, 'UTF-8')"/>
      <xsl:text>&amp;q=</xsl:text>
      <xsl:value-of select="url:encode($term, 'UTF-8')"/>
   </xsl:template>
   <!--
***************************************************************************
solr_narrower_filter: generates url that adds an fq filter to the current query, for a given field and term
	- used e.g. for queries based on facets, to narrow the current result set to just those items that
		contain that facet
-->
   <xsl:template name="solr_narrower_filter">
      <xsl:param name="field"/>
      <xsl:param name="term"/>
      <xsl:param name="baseurl"/>
      <xsl:variable name="facetIsQuery" select="../@name='facet_queries'"/>
      <!-- find the facet configuration for the current facet, which may be a query or a field -->
      <xsl:variable name="facetConfig"
         select="
			$solr_query_config_facets/query[
				$facetIsQuery and 
				. = concat($field, ':', $term)]
			| 
			$solr_query_config_facets/field[
				not($facetIsQuery) and 
				. = $field]
		"/>
      <xsl:choose>
         <xsl:when test="$baseurl = ''">
            <xsl:value-of select="$solr_queryurl"/>
         </xsl:when>
         <xsl:otherwise>
            <xsl:value-of select="$baseurl"/>
         </xsl:otherwise>
      </xsl:choose>
      <xsl:text>&amp;fq=</xsl:text>
      <xsl:if test="$field != ''">
         <xsl:value-of select="$field"/>
         <xsl:text>:</xsl:text>
      </xsl:if>
      <xsl:choose>
         <xsl:when test="$facetConfig/@quote='true'">
            <xsl:value-of select="url:encode(concat('&quot;', $term, '&quot;'), 'UTF-8')"/>
         </xsl:when>
         <xsl:otherwise>
            <xsl:value-of select="url:encode($term, 'UTF-8')"/>
         </xsl:otherwise>
      </xsl:choose>
      <!-- diagnostics: show current facetConfig at the end of the url 
			<xsl:text>&amp;facetConfig=</xsl:text>
			<xsl:value-of select="name($facetConfig)"/>
				<xsl:text> </xsl:text>
				<xsl:for-each select="$facetConfig/@*">
					<xsl:value-of select="name(.)"/>="<xsl:value-of select="."/>" <xsl:text/>
				</xsl:for-each>
				<xsl:text>&gt;</xsl:text>
				<xsl:value-of select="$facetConfig"/>
				<xsl:text>&lt;/</xsl:text>
				<xsl:value-of select="name($facetConfig)"/>
				<xsl:text>&gt;</xsl:text>
	-->
   </xsl:template>
   <!--
***************************************************************************
solr_query_remove_filter: generates url to reproduce the current query, with sort, without navigation, 
	and without the specified filter 
		-used for removing an fq filter from the current query
Called by: solr_remove_filter
-->
   <xsl:template name="solr_queryurl_remove_filter">
      <xsl:param name="filter"/>
      <xsl:param name="filterfield"/>
      <xsl:value-of select="$solr_baseurl"/>
      <xsl:for-each select="$solr_fq">
         <xsl:if
            test="
			    ($filter != '' and . != $filter)
			    or
			    ($filterfield != '' and not(starts-with(., concat($filterfield, ':'))))
			    ">
            <xsl:text>&amp;fq=</xsl:text>
            <xsl:value-of select="url:encode(., 'UTF-8')"/>
         </xsl:if>
      </xsl:for-each>
      <xsl:text>&amp;sort=</xsl:text>
      <xsl:value-of select="url:encode($solr_sort, 'UTF-8')"/>
   </xsl:template>
   <!--
***************************************************************************
solr_toPage: generates url to link to given page of results for the current query
external
-->
   <xsl:template name="solr_toPage">
      <xsl:param name="pagenum"/>
      <xsl:value-of select="$solr_queryurl"/>
      <xsl:text>&amp;start=</xsl:text>
      <xsl:value-of select="$solr_rows * ($pagenum - 1)"/>
   </xsl:template>
   <!--
***************************************************************************
solr_simple_navigation: div containing current page number with links to previous and next pages of results
-->
   <xsl:variable name="solr_pages">
      <xsl:choose>
         <xsl:when test="$solr_numfound !=0">
            <xsl:text>Page </xsl:text>
            <xsl:value-of select="$solr_curpage"/>
            <xsl:text> of </xsl:text>
            <xsl:value-of select="$solr_lastpage"/>
         </xsl:when>
         <xsl:otherwise>No results were found.</xsl:otherwise>
      </xsl:choose>
   </xsl:variable>
   <xsl:variable name="solr_startValue">
      <xsl:choose>
         <xsl:when test="(($solr_curpage - 1) * 10)=0">
            <xsl:text>1</xsl:text>
         </xsl:when>
         <xsl:otherwise>
            <xsl:value-of select="(($solr_curpage -1 ) * 10) + 1"/>
         </xsl:otherwise>
      </xsl:choose>
   </xsl:variable>


   <xsl:template name="solr_simple_navigation">
      <div class="navigation">
         <xsl:if test="$solr_curpage > 1">
            <a>
               <xsl:attribute name="href">
                  <xsl:call-template name="solr_toPage">
                     <xsl:with-param name="pagenum" select="$solr_curpage - 1"/>
                  </xsl:call-template>
               </xsl:attribute>
               <xsl:text>[ Previous ]</xsl:text>
            </a>
         </xsl:if>
         <xsl:text> </xsl:text>
         <xsl:value-of select="$solr_pages"/>
         <xsl:text> </xsl:text>
         <xsl:if test="$solr_curpage &lt; $solr_lastpage">
            <xsl:text>   </xsl:text>
            <a>
               <xsl:attribute name="href">
                  <xsl:call-template name="solr_toPage">
                     <xsl:with-param name="pagenum" select="$solr_curpage + 1"/>
                  </xsl:call-template>
               </xsl:attribute>
               <xsl:text>[ Next ]</xsl:text>
            </a>
         </xsl:if>
      </div>
   </xsl:template>
   <!--
***************************************************************************
solr_show_query: generates series of <li> elements containing user-readable display of query clauses
	note: this is a recursive template: it processes the first clause of the query, then calls itself to process
		the remainder of the query
external
TODO: add "remove" links; merge this list with the list of fq filters
-->
   <xsl:template name="solr_show_query">
      <xsl:param name="q"/>
      <xsl:variable name="qnorm" select="normalize-space($q)"/>
      <xsl:variable name="operator">
         <xsl:if test="starts-with($qnorm, 'AND ') or starts-with($qnorm, 'OR ') or starts-with($qnorm, 'NOT ')">
            <xsl:value-of select="substring-before($qnorm, ' ')"/>
         </xsl:if>
      </xsl:variable>
      <xsl:variable name="element">
         <xsl:choose>
            <xsl:when test="$operator = ''">
               <xsl:value-of select="$qnorm"/>
            </xsl:when>
            <xsl:otherwise>
               <xsl:value-of select="substring-after($qnorm, ' ')"/>
            </xsl:otherwise>
         </xsl:choose>
      </xsl:variable>
      <xsl:variable name="field" select="substring-before($element, ':')"/>
      <xsl:variable name="term" select="substring-after(substring-before($element, ')'), '(')"/>


      <li>
         <xsl:value-of select="$operator"/>
         <xsl:text> </xsl:text>
          <xsl:if test="$field != '*' and not($solr_query_config_fields[. = $field]/@default = 'true')">
            <xsl:value-of select="$solr_query_config_fields[. = $field]/@label"/>
            <xsl:text>: </xsl:text>
         </xsl:if>
         <xsl:value-of select="$term"/>
      </li>
      <xsl:variable name="remainder" select="normalize-space(substring-after($qnorm, ')'))"/>
      <xsl:if test="$remainder != ''">
         <xsl:call-template name="solr_show_query">
            <xsl:with-param name="q" select="$remainder"/>
         </xsl:call-template>
      </xsl:if>
   </xsl:template>
   <!--
***************************************************************************
solr_sort_option: generates one <option> element for a given <value> element in <parameter name="sort"> 
		in the query configuration. Handles the "selected" attribute (based on current sort or default value) and 
		label.
external
-->
   <xsl:template name="solr_sort_option">
      <option value="{.}">
         <xsl:if test="$solr_sort = . or (@default = 'true' and not($solr_sort))">
            <xsl:attribute name="selected"/>
         </xsl:if>
         <xsl:value-of select="@label"/>
      </option>
   </xsl:template>
   <!--
***************************************************************************
solr_facet_group: generates a set of facets for a given facet and facetType (field or query or range). The "style" param
	allows tagcloud or bulleted layout
calls solr_facet_field or solr_facet_query or solr_facet_range, depending on the type of facet
external
-->
   <xsl:template name="solr_facet_group">
      <xsl:param name="facetType">field</xsl:param>
      <xsl:param name="field"/>
      <xsl:param name="style">tagcloud</xsl:param>
      
      <!-- get multifield def from Solr params -->
      <xsl:variable name="def" select="$solr_params/str[@name='c_multifield'][starts-with(., concat($field, ':'))]"/>
      <xsl:variable name="mftype" select="substring-before(substring-after($def, ':'), ':')"/>
      <xsl:variable name="mffield" select="substring-after(substring-after($def, ':'), ':')"/>
      
      <xsl:comment>def: <xsl:value-of select="$def"/>; mftype: <xsl:value-of select="$mftype"/>; mffield: <xsl:value-of select="$mffield"
      /></xsl:comment>
      <!--<xsl:variable name="config" select="$solr_query_config_facets/hierarchy[@type='multifield']/field[@fname=$mffield]"/> -->
      
      <!-- for queries, we want the first <query> config whose value begins with "price:" -->
      <!-- for ranges, we want the one whose gap matches the f.<field>.facet.range.gap -->
      <xsl:variable name="facetConfig"
         select="
		    $solr_query_config_facets/query[
				($facetType = 'query') and 
				starts-with(., concat($field, ':'))][1]
			| 
			$solr_query_config_facets/field[
				($facetType = 'field') and 
				. = $field]
				| 
				$solr_query_config_facets/hierarchy[
				($facetType = 'range') and 
				@fname = $field] 
				| 
				$solr_query_config_facets/hierarchy[
				($facetType = 'multifield') and 
				@name = $field]
				"/>

       <!-- variables for multifield field -->
      <xsl:variable name="hierFields" select="$facetConfig/*"/>
      <!-- choose the fq that matches one of the @breakdown-froms in the hierarchy; there will be only one, 
         since we only ever facet on one of date_y, date_ym, or date_ymd at a time -->
       <xsl:variable name="fq"
           select="$solr_fq[substring-before(., ':') = $hierFields/@breakdown-from]"/>
       <xsl:variable name="fq-term" select="substring-after($fq, ':')"/>
       <xsl:variable name="fq-term-prefix">
           <xsl:choose>
               <xsl:when test="contains($fq-term, ' TO ')"/>
               <xsl:otherwise><xsl:value-of select="$fq-term"/></xsl:otherwise>
           </xsl:choose>
       </xsl:variable>
      <xsl:variable name="fq-term-start" select="translate(substring-before($fq-term, ' TO '), '[', '')"/>
      <xsl:variable name="fq-term-end" select="translate(substring-after($fq-term, ' TO '), ']', '')"/>

      <xsl:variable name="fieldConfig" select="$facetConfig/field[
         @fname=$mffield 
         and 
         starts-with($fq, concat(@breakdown-from, ':'))
         ]"/>
      <xsl:comment>$fq: <xsl:value-of select="$fq"/>; fieldConfig: <xsl:value-of select="concat($fieldConfig/@fname, ':', $fieldConfig/@breakdown-from)"/>
      mftype: <xsl:value-of select="$mftype"/>; mffield: <xsl:value-of select="$mffield"/>
         fq-term-start: <xsl:value-of select="$fq-term-start"/>; fq-term-end: <xsl:value-of select="$fq-term-end"/>; fq-term-prefix: <xsl:value-of select="$fq-term-prefix"/>; </xsl:comment>
      <xsl:variable name="facets"
         select="
			$solr_facet_queries/int[
				($facetType = 'query') and 
				starts-with(@name, concat($field, ':'))]
			| 
			$solr_facet_fields/lst[
				($facetType = 'field') and 
				@name = $field]/int
			|
			$solr_facet_ranges/lst[
			     ($facetType = 'range') and
			     @name = $field]/lst[@name='counts']/int
			     |
         $solr_facet_ranges/lst[
         ($mftype = 'range') and
         @name = $mffield]/lst[@name='counts']/int[starts-with(@name, $fq-term-prefix)]
         |
         $solr_facet_fields/lst[
         ($mftype = 'field') and
         @name = $mffield]/int[
            ($fq-term-start = '' and starts-with(@name, $fq-term-prefix))
            or
            ($fq-term-start != '' and $fq-term-start &lt;= @name and $fq-term-end &gt;= @name) 
         ]
		"/>

        
      <xsl:variable name="isCalendar" select="$facets/../../str[@name='gap'] = '+1DAY'"/>
      <xsl:variable name="output">
         <xsl:choose>
            <xsl:when test="$facetType = 'field'">
               <xsl:for-each select="$facets">
                  <xsl:sort data-type="text" order="ascending" select="@name"/>
                  <xsl:call-template name="solr_facet_field">
                     <xsl:with-param name="field" select="$field"/>
                     <xsl:with-param name="style" select="$style"/>
                  </xsl:call-template>
               </xsl:for-each>
            </xsl:when>
            <xsl:when test="$facetType = 'range'">
               <xsl:choose>
                  <xsl:when test="$isCalendar">
                     <xsl:call-template name="solr_facet_range_calendar">
                        <xsl:with-param name="field" select="$field"/>
                     </xsl:call-template>
                  </xsl:when>
                  <xsl:otherwise>
                     <xsl:for-each select="$facets">
                        <xsl:call-template name="solr_facet_range">
                           <xsl:with-param name="field" select="$field"/>
                           <xsl:with-param name="style" select="$style"/>
                           <xsl:with-param name="type">date</xsl:with-param>
                        </xsl:call-template>
                     </xsl:for-each>
                  </xsl:otherwise>
               </xsl:choose>
            </xsl:when>
            <xsl:when test="$facetType = 'multifield'">
               <xsl:choose>
                  <xsl:when test="$mftype='range'">
                     <!-- we might have reached the lowest level of fields -->
                     <xsl:choose>
                        <xsl:when test="not($solr_fq[starts-with(., 'date_ymd:')])">
                           <xsl:for-each select="$facets">
                              <xsl:call-template name="solr_facet_range">
                                 <xsl:with-param name="field" select="$field"/>
                                 <xsl:with-param name="style" select="$style"/>
                              </xsl:call-template>
                           </xsl:for-each>
                        </xsl:when>
                        <xsl:otherwise>
                           <i18n:date src-pattern="yyyyMMdd" pattern="yyyy, MMMM d" value="{substring-after($solr_fq[starts-with(., 'date_ymd:')], ':')}" xmlns:i18n="http://apache.org/cocoon/i18n/2.1"/>
                        </xsl:otherwise>
                     </xsl:choose>
                  </xsl:when>
                  <xsl:when test="$mftype='field' and $fieldConfig/@display = 'day'">
                     <!-- calendar -->
                     <xsl:call-template name="solr_facet_multifield_calendar">
                        <xsl:with-param name="field" select="$mffield"/>
                        <xsl:with-param name="suppressfq" select="$fieldConfig/@breakdown-from"/>
                     </xsl:call-template>
                  </xsl:when>
                  <xsl:when test="$mftype='field'">
                     <xsl:for-each select="$facets">
                        <xsl:sort data-type="text" order="ascending" select="@name"/>
                        <xsl:call-template name="solr_facet_field">
                           <xsl:with-param name="field" select="$mffield"/>
                           <xsl:with-param name="style" select="$style"/>
                           <xsl:with-param name="suppressfq" select="$fieldConfig/@breakdown-from"/>
                           <xsl:with-param name="display" select="$fieldConfig/@display"/>
                        </xsl:call-template>
                     </xsl:for-each>
                  </xsl:when>

               </xsl:choose>
            </xsl:when>
            <xsl:otherwise>
               <xsl:for-each select="$facets">
                  <xsl:call-template name="solr_facet_query">
                     <xsl:with-param name="field" select="$field"/>
                     <xsl:with-param name="style" select="$style"/>
                  </xsl:call-template>
               </xsl:for-each>
            </xsl:otherwise>
         </xsl:choose>
      </xsl:variable>
      <xsl:variable name="labelfield">
         <xsl:choose>
            <xsl:when test="$mffield != ''">
               <xsl:value-of select="$mffield"/>
            </xsl:when>
            <xsl:otherwise>
               <xsl:value-of select="$field"/>
            </xsl:otherwise>
         </xsl:choose>
      </xsl:variable>
        <span class="label">
            <!-- create suffix with context, if this is a range -->
            <xsl:variable name="range" select="$solr_facet_ranges/lst[@name=$labelfield]"/>
            <xsl:variable name="ymterm"
                select="substring-after($solr_fq[starts-with(., 'date_ym:')], ':')"/>
            <xsl:variable name="ymdterm"
                select="substring-after($solr_fq[starts-with(., 'date_ymd:')], ':')"/>
            <xsl:value-of select="$facetConfig/@group"/>
            <!-- note: if there are no hits, there is no facet section of Solr response -->
            <!-- handle date hierarchy: append date context to group label -->
            <xsl:if
                test="$range/str[@name='gap'] != '+5YEAR' or 
               (starts-with($mffield, 'date_') and not($solr_params/str[@name='facet.range']=$mffield) )">
                <xsl:text> (in </xsl:text>
                <xsl:choose>
                    <xsl:when test="contains($solr_fq[starts-with(., 'date_ymd:')], ' TO ')">
                        <!-- this is a day range for a week query from the calendar display; we just need to display the month -->
                        <i18n:date src-pattern="yyyyMMdd" pattern="yyyy, MMMM d"
                            value="{substring($ymdterm, 2, 8)}"
                            xmlns:i18n="http://apache.org/cocoon/i18n/2.1"/>
                        <xsl:text> to </xsl:text>
                        <i18n:date src-pattern="yyyyMMdd" pattern="d"
                            value="{substring($ymdterm, 14, 8)}"
                            xmlns:i18n="http://apache.org/cocoon/i18n/2.1"/>

                    </xsl:when>
                    <xsl:otherwise>
                        <!-- variables for date ranges -->
                        <xsl:variable name="gap" select="$range/str[@name='gap']"/>
                        <xsl:variable name="termlength">
                            <xsl:choose>
                                <xsl:when test="$gap = '+1YEAR'">4</xsl:when>
                                <xsl:when test="$gap = '+1MONTH'">4</xsl:when>
                                <xsl:when test="$gap = '+1DAY'">6</xsl:when>
                                <xsl:otherwise>100</xsl:otherwise>
                            </xsl:choose>
                        </xsl:variable>
                        <xsl:variable name="suffix-start"
                            select="substring($range/date[@name='start'], 1, $termlength)"/>
                        <xsl:variable name="suffix-end"
                            select="substring($range/date[@name='end'], 1, $termlength)"/>


                        <xsl:choose>
                            <xsl:when test="$gap = '+1DAY'">
                                <i18n:date src-pattern="yyyyMM" pattern="MMMM, yyyy"
                                    value="{$suffix-start}"
                                    xmlns:i18n="http://apache.org/cocoon/i18n/2.1"/>
                            </xsl:when>
                            <xsl:when test="$mffield='date_y'">
                                <xsl:choose>
                                    <xsl:when test="contains($fq-term, ' TO ')">
                                        <xsl:value-of select="substring($fq-term, 2, 4)"/>
                                        <xsl:text>-</xsl:text>
                                        <xsl:value-of select="substring($fq-term, 10, 4)"/>
                                    </xsl:when>
                                    <xsl:otherwise>
                                        <xsl:value-of select="substring($facets[1]/@name, 1, 4)"/>
                                    </xsl:otherwise>
                                </xsl:choose>
                            </xsl:when>
                            <xsl:when test="$mffield='date_ym'">
                                <xsl:value-of select="$fq-term"/>
                            </xsl:when>
                            <xsl:when test="$mffield='date_ymd'">
                                <xsl:choose>
                                    <xsl:when test="contains($ymdterm, ' TO ')"/>
                                    <xsl:otherwise>
                                        <xsl:choose>
                                            <xsl:when test="$ymdterm != ''">
                                        <i18n:date src-pattern="yyyyMM" pattern="MMMM, yyyy"
                                            value="{substring($ymdterm, 1, 6)}"
                                            xmlns:i18n="http://apache.org/cocoon/i18n/2.1"/>
                                            </xsl:when>
                                            <xsl:when test="$ymterm != ''">
                                                <i18n:date src-pattern="yyyyMM" pattern="MMMM, yyyy"
                                                    value="{substring($ymterm, 1, 6)}"
                                                    xmlns:i18n="http://apache.org/cocoon/i18n/2.1"/>
                                            </xsl:when>
                                        </xsl:choose>
                                        <xsl:if test="substring($ymdterm, 7) = '00'">
                                            <xsl:text>: unknown day</xsl:text>
                                        </xsl:if>
                                    </xsl:otherwise>
                                </xsl:choose>
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:value-of select="$suffix-start"/>
                            </xsl:otherwise>
                        </xsl:choose>
                        <xsl:if test="$gap = '+1YEAR'">
                            <xsl:text>-</xsl:text>
                            <xsl:value-of select="number($suffix-end) - 1"/>
                        </xsl:if>
                    </xsl:otherwise>
                </xsl:choose>
                <xsl:text>)</xsl:text>
            </xsl:if>
        </span>
      <xsl:choose>
         <xsl:when test="$isCalendar ">
            <!-- show calendar -->
            <xsl:copy-of select="$output"/>
         </xsl:when>
         <xsl:when test="$style = 'bullets'">
            <ul class="facets_bullets">
               <xsl:copy-of select="$output"/>
            </ul>
         </xsl:when>
         <xsl:when test="$style = 'tagcloud'">
            <div class="facets_tagcloud">
               <xsl:copy-of select="$output"/>
            </div>
         </xsl:when>
         <xsl:otherwise>
            <xsl:copy-of select="$output"/>
         </xsl:otherwise>
      </xsl:choose>
   </xsl:template>
   <!--
***************************************************************************
solr_remove_filter: generate html <li> element containing a display of an fq filter, with a link
  that runs the same query but without that fq
Applies to an "fq" parameter in the Solr response header (e.g. in a for-each applied to $solr_fq)
Parameters: 
	separator: the punctuation that goes between the filter and the removal link
	termSeparator: the punctuation that goes between the field label and the term in the filter display
	text: the anchor text for the removal link
Calls:
	solr_queryurl_remove_filter: builds the url for the removal link
	solr_facet_query_label: displays the label for a facet query

Example of use:

						<ul>
							<xsl:for-each select="$solr_fq">
								<xsl:call-template name="solr_remove_filter"/>
							</xsl:for-each>
						</ul>

TODO: add formatting options beyond <li>
external

context: an fq parameter
-->
   <xsl:template name="solr_remove_filter">
      <xsl:param name="separator">
         <xsl:text> -- </xsl:text>
      </xsl:param>
      <xsl:param name="termSeparator">
         <xsl:text>: </xsl:text>
      </xsl:param>
      <xsl:param name="text">remove filter</xsl:param>
      <xsl:variable name="href">
         <xsl:call-template name="solr_queryurl_remove_filter">
            <xsl:with-param name="filter">
               <xsl:value-of select="."/>
            </xsl:with-param>
         </xsl:call-template>
      </xsl:variable>
      <xsl:variable name="field" select="substring-before(., ':')"/>
      <xsl:variable name="term" select="substring-after(., ':')"/>
      <xsl:variable name="facetType">
         <!-- we assume that a field that has range queries doesn't have field values -->
         <xsl:choose>
            <xsl:when test="$solr_query_config_facets/query[starts-with(., concat($field, ':'))]">query</xsl:when>
            <xsl:when test="$solr_query_config_facets/range[starts-with(., concat($field, ':'))]">range</xsl:when>
            <xsl:otherwise>field</xsl:otherwise>
         </xsl:choose>
      </xsl:variable>
      <!--
      <xsl:variable name="facetConfig"
         select="
			$solr_query_config_facets/query[
				($facetType = 'query') and 
				. = concat($field, ':', $term)]
			| 
			$solr_query_config_facets/field[
				($facetType = 'field') and 
				. = $field]
				| 
				$solr_query_config_facets/range[
				($facetType = 'range') and 
				. = $field]
				"/>
      -->
      <xsl:variable name="facetConfig"
         select="
         $solr_query_config_facets/query[
         ($facetType = 'query') and 
         starts-with(., concat($field, ':'))][1]
         | 
         $solr_query_config_facets/field[
         ($facetType = 'field') and 
         . = $field]
         | 
         $solr_query_config_facets/hierarchy[
         ($facetType = 'range') and 
         @fname = $field] 
         | 
         $solr_query_config_facets/hierarchy[
         field[@fname = $field]]
         "/>
      
      
      
      
      
      <li>
         <xsl:value-of select="$facetConfig/@label"/>
         <xsl:value-of select="$termSeparator"/>
         <xsl:call-template name="solr_facet_query_label">
            <xsl:with-param name="field" select="$field"/>
            <xsl:with-param name="term" select="$term"/>
         </xsl:call-template>
         <xsl:value-of select="$separator"/>
         <a href="{$href}">
            <xsl:value-of select="$text"/>
         </a>
      </li>
   </xsl:template>
   <!-- ***************************************************************************

			Internal Templates

			Not normally calledf by application

	 *************************************************************************** -->
   <!--
***************************************************************************
solr_facet_field: displays a given facet according to the given style (default: tagcloud)
calls solr_facet_display
called by solr_facet_group; not normally called by app
internal
context: /wrapper/response/lst[@name='facet_counts']/lst[@name='facet_fields']/lst[@name=$field]/int
-->
   <xsl:template name="solr_facet_field">
      <!-- current element is $solr_facet_fields/lst/int 
			facet fields look like this:

			<lst name="cat">
				<int name="electronics">2</int>
		-->
      <xsl:param name="field"/>
      <!-- style values: 'tagcloud' or 'bullets' -->
      <xsl:param name="style">tagcloud</xsl:param>
      <!-- non-break space, middot, space - put between items in tag cloud -->
      <xsl:param name="separator">&#160;&#xb7; </xsl:param>
      
      <xsl:param name="suppressfq"/>
      <!-- display can be month or day -->
      <xsl:param name="display"/>
      
      <xsl:variable name="term" select="@name"/>
      <xsl:call-template name="solr_facet_display">
         <xsl:with-param name="field" select="$field"/>
         <xsl:with-param name="term" select="$term"/>
         <xsl:with-param name="style" select="$style"/>
         <xsl:with-param name="separator" select="$separator"/>
         <xsl:with-param name="suppressfq" select="$suppressfq"/>
         <xsl:with-param name="display" select="$display"/>
      </xsl:call-template>
   </xsl:template>
   <!--
***************************************************************************
solr_facet_query: displays a given facet query according to the given style (default: tagcloud)
differs from solr_facet_field only in the method of calculating the field and the term
calls solr_facet_display
called by solr_facet_group; not normally called by app
internal
-->
   <xsl:template name="solr_facet_query">
      <!-- current element is  $solr_facet_queries/int 
		facet queries look like this:

		<lst name="facet_queries">
			<int name="price:[* TO 99.99]">0</int>
		-->
      <!-- style values: 'tagcloud' or 'bullets' -->
      <xsl:param name="style">tagcloud</xsl:param>
      <!-- non-break space, middot, space - put between items in tag cloud -->
      <xsl:param name="separator">&#160;&#xb7; </xsl:param>
      <xsl:variable name="field" select="substring-before(@name, ':')"/>
      <xsl:variable name="term" select="substring-after(@name, ':')"/>
      <xsl:call-template name="solr_facet_display">
         <xsl:with-param name="field" select="$field"/>
         <xsl:with-param name="term" select="$term"/>
         <xsl:with-param name="style" select="$style"/>
         <xsl:with-param name="separator" select="$separator"/>
      </xsl:call-template>
   </xsl:template>
   <!--
***************************************************************************
solr_facet_range: displays a given facet query according to the given style (default: tagcloud)
differs from solr_facet_field only in the method of calculating the field and the term
calls solr_facet_display
called by solr_facet_group; not normally called by app
internal
-->
   <xsl:template name="solr_facet_range">
      <!-- current element is  $solr_facet_ranges/lst[@name='counts']/int 
		facet ranges look like this:
        
        <lst name="facet_ranges">
            <lst name="date">
                <lst name="counts">
                    <int name="1881-01-01T12:00:00Z">1</int>
                    <int name="1896-01-01T12:00:00Z">4</int>
                    <int name="1901-01-01T12:00:00Z">2</int>
                </lst>
                <str name="gap">+5YEAR</str>
                <date name="start">1876-01-01T12:00:00Z</date>
                <date name="end">1921-01-01T12:00:00Z</date>
            </lst>
        </lst>
		-->
      <!-- style values: 'tagcloud' or 'bullets' -->
      <xsl:param name="style">tagcloud</xsl:param>
      <!-- type values: string, date -->
      <xsl:param name="type">string</xsl:param>
      <!-- non-break space, middot, space - put between items in tag cloud -->
      <xsl:param name="separator">&#160;&#xb7; </xsl:param>

      <xsl:variable name="field" select="../../@name"/>
      <xsl:variable name="gap">
         <xsl:choose>
            <xsl:when test="contains(./../str[@name='gap'], '-1DAY')">
               <xsl:value-of select="substring-before(../../str[@name='gap'], '-1DAY')"/>
            </xsl:when>
            <xsl:otherwise>
               <xsl:value-of select="../../str[@name='gap']"/>
            </xsl:otherwise>               
         </xsl:choose>
      </xsl:variable> 
      <xsl:variable name="start" select="../../date[@name='start']"/>
      <xsl:variable name="end" select="../../date[@name='end']"/>

      <xsl:variable name="config"
         select="
            $solr_query_config_facets/hierarchy[@fname = $field and $type = 'date']/range[concat(@gap-operator, @gap-quantum, @gap-unit) = $gap]
           |
           $solr_query_config_facets/hierarchy[@type='multifield' and $type = 'string']/range[@fname = $field]
         "/>
      
      
      <xsl:comment>hierarchy: <xsl:value-of select="count($solr_query_config_facets/hierarchy[@fname=$field]/range)"/> facet gap: <xsl:value-of
            select="$gap"/> gap: <xsl:value-of select="concat($config/@gap-operator, $config/@gap-quantum, $config/@gap-unit)"/></xsl:comment>
      <!-- the term needs be modified to suit the gap: e.g. if gap is +5YEAR, term changes from 1881-01-01T12:0000Z to 1881-1885 -->
      <xsl:variable name="termlength">
         <xsl:choose>
            <xsl:when test="$config/@gap-unit = 'YEAR'">4</xsl:when>
            <xsl:when test="$config/@gap-unit = 'MONTH'">6</xsl:when>
            <xsl:when test="$config/@gap-unit = 'DAY'">8</xsl:when>
            <xsl:otherwise>100</xsl:otherwise>
         </xsl:choose>
      </xsl:variable>
      <xsl:variable name="termdisplay">
         <xsl:choose>
            <xsl:when test="$config/@gap-quantum = 1">
               <xsl:value-of select="substring(@name, 1, $termlength)"/>
            </xsl:when>
            <xsl:otherwise>
               <xsl:choose>
                  <xsl:when test="$type = 'date'">
                     <xsl:value-of select="substring(@name, 1, $termlength)"/>
                     <xsl:text>-</xsl:text>
                     <xsl:value-of select="number(substring(@name, 1, $termlength)) + $config/@gap-quantum"/>
                  </xsl:when>
                  <xsl:otherwise>
                     <xsl:value-of select="@name"/>
                     <xsl:text>-</xsl:text>
                     <xsl:value-of select="number(@name) + $config/@gap - 1"/>
                  </xsl:otherwise>
               </xsl:choose>
            </xsl:otherwise>
         </xsl:choose>
      </xsl:variable>

      <xsl:variable name="term">
         <xsl:text>[</xsl:text>
         <xsl:value-of select="@name"/>
         <xsl:if test="$type = 'date'">
            <xsl:text>/</xsl:text>
            <xsl:value-of select="$config/@gap-unit"/>
         </xsl:if>
         <xsl:text> TO </xsl:text>
         <xsl:choose>
            <xsl:when test="$type = 'date'">
               <xsl:value-of select="@name"/>
               <xsl:text>/</xsl:text>
               <xsl:value-of select="$config/@gap-unit"/>
               <xsl:value-of select="concat($config/@gap-operator,$config/@gap-quantum,$config/@gap-unit)"/>
               <xsl:text>-1DAY</xsl:text>
            </xsl:when>
            <xsl:otherwise>
               <xsl:value-of select="@name + $config/@gap - 1"/>
            </xsl:otherwise>
         </xsl:choose>
         <xsl:text>]</xsl:text>
      </xsl:variable>
      <xsl:comment>type: <xsl:value-of select="$type"/></xsl:comment>
      <xsl:call-template name="solr_facet_display">
         <xsl:with-param name="field" select="$field"/>
         <xsl:with-param name="termdisplay" select="$termdisplay"/>
         <xsl:with-param name="term" select="$term"/>
         <xsl:with-param name="style" select="$style"/>
         <xsl:with-param name="separator" select="$separator"/>
         <xsl:with-param name="suppressfq" select="$field"/>
      </xsl:call-template>
   </xsl:template>
   <!--
***************************************************************************
solr_facet_range: displays a given facet query according to the given style (default: tagcloud)
differs from solr_facet_field only in the method of calculating the field and the term
calls solr_facet_display
called by solr_facet_group; not normally called by app
internal
-->
   <xsl:template name="solr_facet_range_calendar">
      <!-- current element is  $solr_facet_ranges/lst[@name='counts']/int 
		facet ranges look like this:
        
        <lst name="facet_ranges">
            <lst name="date">
                <lst name="counts">
                    <int name="1881-01-01T12:00:00Z">1</int>
                    <int name="1896-01-01T12:00:00Z">4</int>
                    <int name="1901-01-01T12:00:00Z">2</int>
                </lst>
                <str name="gap">+5YEAR</str>
                <date name="start">1876-01-01T12:00:00Z</date>
                <date name="end">1921-01-01T12:00:00Z</date>
            </lst>
        </lst>
		-->
      <!-- style values: 'tagcloud' or 'bullets' -->
      <xsl:param name="style">tagcloud</xsl:param>
      <xsl:param name="field"/>
      <!-- non-break space, middot, space - put between items in tag cloud -->
      <xsl:param name="separator">&#160;&#xb7; </xsl:param>

      <xsl:variable name="range" select="$solr_facet_ranges/lst[@name = $field]"/>

      <xsl:variable name="facets" select="$range/lst[@name='counts']/int"/>

      <xsl:variable name="gap" select="$range/str[@name='gap']"/>
      <xsl:variable name="start" select="$range/date[@name='start']"/>
      <xsl:variable name="end" select="$range/date[@name='end']"/>

      <xsl:variable name="year" select="substring($start, 1, 4)"/>
      <xsl:variable name="month" select="substring($start, 5, 2)"/>

      <xsl:variable name="calendar" select="document(concat('cocoon:/generatecalendar.xml?month=', $month, '&amp;year=', $year))/calendar:calendar"/>

      <xsl:variable name="config"
         select="$solr_query_config_facets/hierarchy[@fname = $field]/range[concat(@gap-operator, @gap-quantum, @gap-unit) = $gap]"/>

      <xsl:variable name="termlength">10</xsl:variable>
      <xsl:variable name="monthname" select="$calendar/@month"/>
       <!-- css:
           .calendar {border-collapse:collapse}
           .calendar th {vertical-align:top; padding:2px; margin:0px; border:1px solid black; width:3em;}
           .calendar td {vertical-align:top; padding:2px; margin:0px; border:1px solid black; width:3em; color:grey; text-align: right;}
           .calendar .right {text-align: right;}
           .calendar .center {text-align: center;}
           .calendar .left {float: left; text-align: left}
           .calendar .right {float: right; text-align: right}
           .calendar .hits {margin-left:auto; margin-right:auto}
           -->
      <table class="calendar">
         <tr>
            <th >S</th>
            <th >M</th>
            <th >T</th>
            <th >W</th>
            <th >T</th>
            <th >F</th>
            <th >S</th>
         </tr>
         <xsl:for-each select="$calendar/calendar:week">
            <tr>
               <xsl:for-each select="calendar:day">
                  <td >
                     <xsl:choose>
                        <xsl:when test="starts-with(@date, $monthname)">
                           <xsl:variable name="day" select="@number"/>
                           <xsl:variable name="dayfacet" select="$facets[number(substring(@name, 7, 2)) = $day]"/>
                           <xsl:choose>
                              <xsl:when test="$dayfacet">
                                 <xsl:for-each select="$dayfacet">
                                    <xsl:variable name="termdisplay">
                                       <xsl:value-of select="$day"/>
                                    </xsl:variable>

                                    <xsl:variable name="term">
                                       <xsl:text>[</xsl:text>
                                       <xsl:value-of select="@name"/>
                                       <xsl:text> TO </xsl:text>
                                       <xsl:value-of select="@name"/>
                                       <xsl:value-of select="concat($config/@gap-operator,$config/@gap-quantum,$config/@gap-unit)"/>
                                       <xsl:text>]</xsl:text>
                                    </xsl:variable>
                                    <xsl:call-template name="solr_facet_display">
                                       <xsl:with-param name="field" select="$field"/>
                                       <xsl:with-param name="termdisplay" select="$termdisplay"/>
                                       <xsl:with-param name="term" select="$term"/>
                                       <xsl:with-param name="style">calendar</xsl:with-param>
                                       <xsl:with-param name="separator" select="$separator"/>
                                       <xsl:with-param name="suppressfq" select="$field"/>
                                    </xsl:call-template>
                                 </xsl:for-each>
                              </xsl:when>
                              <xsl:otherwise>
                                 <xsl:value-of select="@number"/>
                              </xsl:otherwise>
                           </xsl:choose>
                        </xsl:when>
                        <xsl:otherwise>&#160;</xsl:otherwise>
                     </xsl:choose>
                  </td>
               </xsl:for-each>
            </tr>
         </xsl:for-each>
      </table>
   </xsl:template>
   
   <!--
***************************************************************************
solr_facet_range: displays a given facet query according to the given style (default: tagcloud)
differs from solr_facet_field only in the method of calculating the field and the term
calls solr_facet_display
called by solr_facet_group; not normally called by app
internal
-->
   <xsl:template name="solr_facet_multifield_calendar">
      <!-- current element is  $solr_facet_ranges/lst[@name='counts']/int 
		facet ranges look like this:
        
        <lst name="facet_ranges">
            <lst name="date">
                <lst name="counts">
                    <int name="1881-01-01T12:00:00Z">1</int>
                    <int name="1896-01-01T12:00:00Z">4</int>
                    <int name="1901-01-01T12:00:00Z">2</int>
                </lst>
                <str name="gap">+5YEAR</str>
                <date name="start">1876-01-01T12:00:00Z</date>
                <date name="end">1921-01-01T12:00:00Z</date>
            </lst>
        </lst>
		-->
       <xsl:param name="field"/>
      <xsl:param name="suppressfq"/>

       <xsl:variable name="fq" select="$solr_fq[starts-with(., concat($suppressfq, ':'))]"/>
       <xsl:variable name="fqterm" select="substring-after($fq, ':')"/>

      <xsl:variable name="facets"
          select="$solr_facet_fields/lst[@name = $field]/int[starts-with(@name, $fqterm)]
         "/>
 
      <xsl:variable name="year">
         <xsl:choose>
            <xsl:when test="$facets">
               <xsl:value-of select="substring($facets[@name != ''][1]/@name, 1, 4)"/>
            </xsl:when>
            <xsl:otherwise>
               <xsl:value-of select="substring($fqterm, 1, 4)"/>
            </xsl:otherwise>
         </xsl:choose>
      </xsl:variable>
      <xsl:variable name="month">
         <xsl:choose>
            <xsl:when test="$facets">
               <xsl:value-of select="substring($facets[@name != ''][1]/@name, 5, 2)"/>
            </xsl:when>
            <xsl:otherwise>
               <xsl:value-of select="substring($fqterm, 5, 2)"/>
            </xsl:otherwise>
         </xsl:choose>
      </xsl:variable> 
      
      <xsl:variable name="calendar" select="document(concat('cocoon:/generatecalendar.xml?month=', $month, '&amp;year=', $year))/calendar:calendar"/>
      
 <!--     <xsl:variable name="config"
         select="$solr_query_config_facets/hierarchy[@fname = $field]/range[concat(@gap-operator, @gap-quantum, @gap-unit) = $gap]"/>
     --> 
      <xsl:variable name="monthname" select="$calendar/@month"/>
      
      
      <table class="calendar" >
         <tr>
            <th>&#160;</th>
            <th >S</th>
            <th >M</th>
            <th >T</th>
            <th >W</th>
            <th >T</th>
            <th >F</th>
            <th >S</th>
         </tr>
         <xsl:for-each select="$calendar/calendar:week">
            <tr>
               <!-- search whole week -->
               <td >
                  <xsl:variable name="firstdaynum" select="calendar:day[starts-with(@date, $monthname)][1]/@number"/>
                  <xsl:variable name="lastdaynum" select="calendar:day[starts-with(@date, $monthname)][last()]/@number"/>
                  <xsl:variable name="firstday" select="concat($year,  $month,  format-number($firstdaynum, '00'))"/>
                  <xsl:variable name="lastday" select="concat($year,  $month,  format-number($lastdaynum, '00'))"/>
                  <xsl:variable name="term" select="concat('[', $firstday, ' TO ', $lastday, ']')"/>
                  
                  <xsl:variable name="hits" select="sum($facets[number(substring(@name, 7)) &gt;= $firstdaynum and number(substring(@name, 7)) &lt;= $lastdaynum])"/>
                  <xsl:variable name="termdisplay" select="concat ('W', @number)"/>
                  
                  <xsl:choose>
                     <xsl:when test="$hits &gt; 0">
                        <xsl:call-template name="solr_facet_display">
                           <xsl:with-param name="field" select="$field"/>
                           <xsl:with-param name="termdisplay" select="$termdisplay"/>
                           <xsl:with-param name="term" select="$term"/>
                           <xsl:with-param name="style">calendar</xsl:with-param>
                           <!-- TODO make sure this still works for ranges; was $field -->
                           <xsl:with-param name="suppressfq" select="$suppressfq"/>
                           <xsl:with-param name="hits" select="$hits"/>
                        </xsl:call-template>
                     </xsl:when>
                     <xsl:otherwise>
                        <xsl:value-of select="$termdisplay"/>
                     </xsl:otherwise>
                  </xsl:choose>
                  
               </td>
               <xsl:for-each select="calendar:day">
                  <td >
                     <xsl:choose>
                        <xsl:when test="starts-with(@date, $monthname)">
                           <xsl:variable name="day" select="@number"/>
                           <xsl:variable name="dayfacet" select="$facets[number(substring(@name, 7, 2)) = $day]"/>
                           <xsl:choose>
                              <xsl:when test="$dayfacet">
                                 <xsl:for-each select="$dayfacet">
                                    <xsl:variable name="termdisplay">
                                       <xsl:value-of select="$day"/>
                                    </xsl:variable>
                                    
                                    <xsl:variable name="term">
                                       <xsl:value-of select="@name"/>
                                    </xsl:variable>
                                    <xsl:call-template name="solr_facet_display">
                                       <xsl:with-param name="field" select="$field"/>
                                       <xsl:with-param name="termdisplay" select="$termdisplay"/>
                                       <xsl:with-param name="term" select="$term"/>
                                       <xsl:with-param name="style">calendar</xsl:with-param>
                                       <!-- TODO make sure this still works for ranges; was $field -->
                                       <xsl:with-param name="suppressfq" select="$suppressfq"/>
                                    </xsl:call-template>
                                 </xsl:for-each>
                              </xsl:when>
                              <xsl:otherwise>
                                 <xsl:value-of select="@number"/>
                              </xsl:otherwise>
                           </xsl:choose>
                        </xsl:when>
                        <xsl:otherwise>&#160;</xsl:otherwise>
                     </xsl:choose>
                  </td>
               </xsl:for-each>
            </tr>
         </xsl:for-each>
         <xsl:if test="$facets[substring(@name, 7) = '00']">
         <tr>
            <td colspan="8" class="center">
               <xsl:call-template name="solr_facet_display">
                  <xsl:with-param name="field" select="$field"/>
                  <xsl:with-param name="termdisplay" select="'Unknown day'"/>
                  <xsl:with-param name="term" select="$facets[substring(@name, 7) = '00']/@name"/>
                  <xsl:with-param name="style">calendar</xsl:with-param>
                  <!-- TODO make sure this still works for ranges; was $field -->
                  <xsl:with-param name="suppressfq" select="$suppressfq"/>
                  <xsl:with-param name="hits" select="$facets[substring(@name, 7) = '00']"/>
               </xsl:call-template>
            </td>
         </tr>
         </xsl:if>
         <tr>
            <td colspan="8" >
               <div class="left">
                  <xsl:call-template name="solr_facet_display">
                     <xsl:with-param name="field" select="'date_ym'"/>
                     <xsl:with-param name="termdisplay" select="'⇐Prev'"/>
                     <xsl:with-param name="term" select="concat($calendar/@prevYear,  $calendar/@prevMonth)"/>
                     <xsl:with-param name="style">calendar</xsl:with-param>
                     <!-- TODO make sure this still works for ranges; was $field -->
                     <xsl:with-param name="suppressfq" select="$suppressfq"/>
                     <xsl:with-param name="hits" select="0"/>
                  </xsl:call-template>
                  
               </div>
               <div class="right">                  
                  <xsl:call-template name="solr_facet_display">
                     <xsl:with-param name="field" select="'date_ym'"/>
                     <xsl:with-param name="termdisplay" select="'Next⇒'"/>
                     <xsl:with-param name="term" select="concat($calendar/@nextYear, $calendar/@nextMonth)"/>
                     <xsl:with-param name="style">calendar</xsl:with-param>
                     <!-- TODO make sure this still works for ranges; was $field -->
                     <xsl:with-param name="suppressfq" select="$suppressfq"/>
                     <xsl:with-param name="hits" select="0"/>
                  </xsl:call-template>
               </div>
            </td>
         </tr>
      </table>
   </xsl:template>
   
   <!--
***************************************************************************
solr_facet_display: generates the html display of a facet, including the <a> element and, if style is "bulleted", the <li> element
called by solr_facet_field and solr_facet_query and solr_facet_range; not normally called by app
internal
context: /wrapper/response/lst[@name='facet_counts']/lst[@name='facet_fields']/lst[@name=$field]/int

	-->
   <xsl:template name="solr_facet_display">
      <xsl:param name="field"/>
      <xsl:param name="termdisplay"/>
      <xsl:param name="term"/>
      <xsl:param name="style"/>
      <xsl:param name="separator"/>
      <xsl:param name="suppressfq"/>
      <xsl:param name="display"/>
      <xsl:param name="hits"/>
      <!-- diagnostic: show current facetConfig in a comment
		<xsl:variable name="facetConfig" select="
			$solr_query_config_facets/query[
				current()/../@name='facet_queries' and 
				. = concat($field, ':', $term)]
			| 
			$solr_query_config_facets/field[
				not(current()/../@name = 'facet_queries') and 
				. = $field]
		"/>		
			<xsl:comment>
				facetConfig: &lt;<xsl:value-of select="name($facetConfig)"/>
				<xsl:text> </xsl:text>
				<xsl:for-each select="$facetConfig/@*">
					<xsl:value-of select="name(.)"/>="<xsl:value-of select="."/>" <xsl:text/>
				</xsl:for-each>
				<xsl:text>&gt;</xsl:text>
				<xsl:value-of select="$facetConfig"/>
				<xsl:text>&lt;/</xsl:text>
				<xsl:value-of select="name($facetConfig)"/>
				<xsl:text>&gt;</xsl:text>
			</xsl:comment>
		-->
      <xsl:variable name="termlabel">
         <xsl:choose>
            <xsl:when test="$termdisplay != ''">
               <xsl:value-of select="$termdisplay"/>
            </xsl:when>
            <xsl:otherwise>
               <xsl:value-of select="$term"/>
            </xsl:otherwise>
         </xsl:choose>
      </xsl:variable>
      <!-- filter out empties -->
      <xsl:if test="normalize-space($termlabel) != ''">
         <xsl:variable name="baseurl">
            <xsl:if test="$suppressfq != ''">
               <xsl:call-template name="solr_queryurl_remove_filter">
                  <xsl:with-param name="filterfield">
                     <xsl:value-of select="$suppressfq"/>
                  </xsl:with-param>
               </xsl:call-template>
            </xsl:if>
         </xsl:variable>
         <xsl:variable name="queryurl">
            <xsl:call-template name="solr_narrower_filter">
               <xsl:with-param name="field" select="$field"/>
               <xsl:with-param name="term" select="$term"/>
               <xsl:with-param name="baseurl" select="$baseurl"/>
            </xsl:call-template>
         </xsl:variable>
         <xsl:variable name="hitcount">
            <xsl:choose>
               <xsl:when test="$hits != ''">
                  <xsl:value-of select="$hits"/>
               </xsl:when>
               <xsl:otherwise>
                  <xsl:value-of select="."/>
               </xsl:otherwise>
            </xsl:choose>
         </xsl:variable>
         <xsl:variable name="nResults">
            <xsl:if test="$hitcount &gt; 0">
                <!-- was ": 10 hits" -->
                <xsl:text>&#160;(</xsl:text>
               <xsl:value-of select="$hitcount"/>
               <xsl:text>)</xsl:text>
               
            </xsl:if>
         </xsl:variable>
          <xsl:variable name="nResults-title">
              <xsl:if test="$hitcount &gt; 0">
                  <xsl:value-of select="$hitcount"/>
                  <xsl:text> result</xsl:text>
                  <xsl:if test="$hitcount &gt; 1">s</xsl:if>
              </xsl:if>
          </xsl:variable>
          <xsl:choose>
            <xsl:when test="$style='tagcloud'">
               <xsl:variable name="percentage">
                  <xsl:value-of select="(. div $solr_numfound) * 100"/>
               </xsl:variable>
               <xsl:variable name="fontSize" select="ceiling($percentage div 10)"/>
               <!-- gives result as integer between 1 and 10 -->
               <a title="{$nResults-title}" class="tagcloud{$fontSize}" href="{$queryurl}">
                  <xsl:call-template name="solr_facet_query_label">
                     <xsl:with-param name="field" select="$field"/>
                     <xsl:with-param name="term" select="$termlabel"/>
                     <xsl:with-param name="display" select="$display"/>
                  </xsl:call-template>
               </a>
               <xsl:if test="position() != last()">
                  <xsl:value-of select="$separator"/>
               </xsl:if>
            </xsl:when>
            <xsl:when test="$style='calendar'">
               <span class="hits" >
                  <a title="{$nResults-title}" href="{$queryurl}" >
                     <xsl:value-of select="$termlabel"/>
                  </a>
               </span>
            </xsl:when>
            <xsl:when test="$style='bullets'">
               <li>
                  <xsl:attribute name="class">
                     <xsl:text>facet-with-</xsl:text>
                     <xsl:if test=". = 0">no-</xsl:if>
                     <xsl:text>hits</xsl:text>
                  </xsl:attribute>
                  <xsl:choose>
                     <xsl:when test=". &gt; 0">
                        <a title="{$nResults-title}" href="{$queryurl}">
                           <xsl:call-template name="solr_facet_query_label">
                              <xsl:with-param name="field" select="$field"/>
                              <xsl:with-param name="term" select="$termlabel"/>
                              <xsl:with-param name="display" select="$display"/>
                           </xsl:call-template>
                        </a>
                     </xsl:when>
                     <xsl:otherwise>
                        <!-- if there are no hits, do not link -->
                        <xsl:call-template name="solr_facet_query_label">
                           <xsl:with-param name="field" select="$field"/>
                           <xsl:with-param name="term" select="$termlabel"/>
                           <xsl:with-param name="display" select="$display"/>
                        </xsl:call-template>
                     </xsl:otherwise>
                  </xsl:choose>
                  <xsl:value-of select="$nResults"/>
               </li>
            </xsl:when>
         </xsl:choose>
      </xsl:if>
   </xsl:template>
   <!--
***************************************************************************
solr_facet_query_label: display a facet query term, replacing it with a label from the facetConfig if present
internal
-->
   <xsl:template name="solr_facet_query_label">
      <xsl:param name="field"/>
      <xsl:param name="term"/>
      <xsl:param name="display"/>
      <xsl:variable name="facetType">
         <!-- we assume that a field that has range queries doesn't have field values -->
         <xsl:choose>
            <xsl:when test="$solr_query_config_facets/query[starts-with(., concat($field, ':'))]">query</xsl:when>
            <xsl:otherwise>field</xsl:otherwise>
         </xsl:choose>
      </xsl:variable>
      <xsl:variable name="facetConfig"
         select="
			$solr_query_config_facets/query[
				($facetType = 'query') and 
				. = concat($field, ':', $term)]
			| 
			$solr_query_config_facets/field[
				($facetType = 'field') and 
				. = $field]
		"/>
      <!-- $facetConfig is like these:

			<field label="Status" label_true="In stock" label_false="Out of stock">inStock</field>
			<field label="Manufacturer" quote="true">manu_exact</field>
			
		-->
      <xsl:comment><xsl:value-of select="$field"/>:<xsl:value-of select="$term"/></xsl:comment>

      <xsl:choose>
         <!-- is this a facet query? If so, we want to display the label attribute from the facet query configuration, e.g. 
					<query label="under $100">price:[* TO 99.99]</query>
				-->
         <xsl:when test="$facetConfig/@label_value">
            <xsl:value-of select="$facetConfig/@label_value"/>
         </xsl:when>
         <!-- if there is a label attribute for this term (e.g. @label_term), use it; otherwise show term; e.g.
						<field label="Status" label_true="In stock" label_false="Out of stock">inStock</field>
					 -->
         <xsl:when test="$facetConfig/@*[name() = concat('label_', $term)]">
            <xsl:value-of select="$facetConfig/@*[name() = concat('label_', $term)]"/>
         </xsl:when>
         
         <!-- year range -->
         <xsl:when test="$field='date_y' and contains($term, ' TO ')">
            <xsl:value-of select="substring($term, 2, 4)"/>
            <xsl:text>-</xsl:text>
            <xsl:value-of select="substring($term, 10, 4)"/>
         </xsl:when>

         <!-- month -->
         <xsl:when test="../../str[@name='gap']='+1MONTH' or $display='month'">
            <xsl:choose>
               <xsl:when test="substring($term, 5) = '00'">Unknown month</xsl:when>
               <xsl:otherwise>
                  <i18n:date src-pattern="yyyyMM" pattern="MMMM" value="{$term}" xmlns:i18n="http://apache.org/cocoon/i18n/2.1"/>
               </xsl:otherwise>
            </xsl:choose>
         </xsl:when>
         <!-- month + year -->
         <xsl:when test="$field='date_ym'">
            <xsl:choose>
               <xsl:when test="substring($term, 5) = '00'"><xsl:value-of select="substring($term, 1, 4)"/>, unknown month</xsl:when>
               <xsl:otherwise>
                  <i18n:date src-pattern="yyyyMM" pattern="yyyy, MMMM" value="{$term}" xmlns:i18n="http://apache.org/cocoon/i18n/2.1"/>
               </xsl:otherwise>
            </xsl:choose>
            
         </xsl:when>
         <!-- day -->
         <xsl:when test="../../str[@name='gap']='+1DAY' or $display='day'">
            <xsl:choose>
               <xsl:when test="substring($term, 7)='00'">Unknown day</xsl:when>
               <xsl:otherwise>
                  <i18n:date src-pattern="yyyyMMdd" pattern="d" value="{$term}" xmlns:i18n="http://apache.org/cocoon/i18n/2.1"/>
               </xsl:otherwise>
            </xsl:choose>
         </xsl:when>
         <!-- day + month + year -->
         <xsl:when test="$field='date_ymd'">
            <!-- for now we assume these dates are within the same month -->
            <xsl:variable name="isRange" select="contains($term, ' TO ')"/>
            <xsl:choose>
               <xsl:when test="$isRange">
                  <i18n:date src-pattern="yyyyMMdd" pattern="yyyy, MMMM d" value="{substring($term, 2, 8)}" xmlns:i18n="http://apache.org/cocoon/i18n/2.1"/>
                  <xsl:text> to </xsl:text>
                  <i18n:date src-pattern="yyyyMMdd" pattern="d" value="{substring($term, 14, 8)}" xmlns:i18n="http://apache.org/cocoon/i18n/2.1"/>
               </xsl:when>
               <xsl:otherwise>
                  <xsl:choose>
                     <xsl:when test="substring($term, 7) = '00'"><i18n:date src-pattern="yyyyMMdd" pattern="yyyy, MMMM" value="{$term}"
                           xmlns:i18n="http://apache.org/cocoon/i18n/2.1"/>, unknown day</xsl:when>
                     <xsl:otherwise>
                        <i18n:date src-pattern="yyyyMMdd" pattern="yyyy, MMMM d" value="{$term}" xmlns:i18n="http://apache.org/cocoon/i18n/2.1"/>
                     </xsl:otherwise>
                  </xsl:choose>
               </xsl:otherwise>
            </xsl:choose>
           </xsl:when>
         <xsl:otherwise>
            <xsl:value-of select="$term"/>
         </xsl:otherwise>
      </xsl:choose>
   </xsl:template>
   <!-- ***************************************************************************

			Search form templates - not yet in use

		TODO: finish this

	 *************************************************************************** -->
   <xsl:template name="solr_form">
      <!-- applies to query element in solrqueries.xml -->
      <xsl:param name="numboxes">3</xsl:param>
      <xsl:variable name="fields">
         <select name="field">
            <xsl:for-each select="fields/field">
               <option value="{.}">
                  <xsl:if test="@default='true'">
                     <xsl:attribute name="selected">true</xsl:attribute>
                  </xsl:if>
                  <xsl:choose>
                     <xsl:when test="@label">
                        <xsl:value-of select="@label"/>
                     </xsl:when>
                     <xsl:otherwise>
                        <xsl:value-of select="."/>
                     </xsl:otherwise>
                  </xsl:choose>
               </option>
            </xsl:for-each>
         </select>
      </xsl:variable>
      <form action="result.html" method="get">
         <table>
            <tbody>
               <tr>
                  <td>
                     <span class="label">Search</span>
                  </td>
                  <td>
                     <input type="text" name="q"/>
                  </td>
                  <td>in</td>
                  <td>
                     <xsl:copy-of select="$fields"/>
                  </td>
               </tr>
            </tbody>
         </table>
      </form>
   </xsl:template>
</xsl:stylesheet>
