cocoonsolr
==========

Cocoon management of Solr queries and results

#Usage:

##sitemap.xmap 
* should be well known to Cocoon projects

    <map:generate type="request" label="request"/>
    <map:transform src="cocoonsolr/solrquery.xsl" label="solr2">
      <map:parameter name="solr" value="http://{global:solr}/select?"/>
      <!-- use of contextpath input module gives us an absolute path, so cocoonsolr doesn't have
           to incorporate any assumptions about the location of app resources -->
      <map:parameter name="solrquery" value="{contextpath:.}/solrqueries.xml"/>
      <map:parameter name="queryID" value="main"/>
    </map:transform>
    <map:transform type="cinclude" label="solr3"/>
    <!--- do what you want with the solr response and serialize -->

##solrqueries.xml  
* defines default parameter for queries you define for your project
* this is a paired down example which demonstrates the basic elements of the file
* this is input to the solrquery.xsl transform and typically lives in the base directory of your Cocoon project

    <!-- version of Solr -->
    <solr version="1.2">
      <query id="main">
        <!-- permitted fields -->
        <fields>
          <field label="any" default="true">text</field>
          <field label="ID">unitid</field>
          <field label="Subject">subject</field>
        </fields>
        <!-- query parameters that can be affected by user input: navigational, sort, etc. -->
        <parameters>
          <parameter name="sort">
            <value default="true" label="Relevance"/>
            <value label="ID">id asc</value>
          </parameter>
        </parameters>
        <!-- parameters defined by the application, not affected by user input -->
        <application>
          <parameter name="echoParams">all</parameter>
        </application>
        <!-- if facets element is here, will set facet=true -->
        <facets attr_mincount="1">
          <field group="Subjects" label="Subject" quote="true">subjectdisplay</field>
        </facets>
        <!-- permitted fields for filter queries -->
        <filters>
          <filter>subjectdisplay</filter>
        </filters>
        <!-- permitted fields etc. for highlighting -->
        <highlighting attr_snippets="1">
          <field>text</field>
        </highlighting>
      </query>
    </solr>

## Request
* parameters passed via a GET or POST request to the pipeline where cocoonsolr operates

q         
* contains search terms from a form
* may have multiple instances, each should be accompanied by a "field" parameter 
* may be accompanied by an operator

field
* contains the name of the field to be searched
* if it is blank or absent no field prefix will be attached to the search term
* optional

operator
* contain boolean operators to be inserted between search terms
* default is AND
* values = {OR, AND}

qq
* pre-composed query