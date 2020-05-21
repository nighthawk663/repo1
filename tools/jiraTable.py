#!/usr/bin/env python3
# Creates a class that can be used to create a document v1 formatted table
# for use in JIRA tickets. Will need to be converted to JSON as part of the 
# larger description.
# https://developer.atlassian.com/cloud/jira/platform/apis/document/nodes/table/
# 
# Len Krygsman IV, 2020/05/21

class jiraTable:
    def __init__(self,columns):
        self.columns = columns
        self.table = {
            "type": "table",
            "attrs" : { "isNumberColumnEnabled" : False, "layout" : "default"},
            "content" : []
            }
    def addRow(self,*args):
        if len(args) != self.columns:
            raise ValueError(f"Number of arguments must equal the number of columns table was initiated with. Expected:{self.columns} Got: {len(args)}")
        row = {
            'type' : 'tableRow',
            'content' : []
        }
        for cellText in args:
            row['content'].append({
                'type': 'tableCell',
                'attrs': {},
                'content' : [{
                    'type': 'paragraph',
                    'content' : [{
                        'type': 'text',
                        'text': str(cellText)
                    }]
                }]
            })
        self.table['content'].append(row)
    def addHeader(self,*args):
        if len(args) != self.columns:
            raise ValueError(f"Number of arguments must equal the number of columns table was initiated with. Expected:{self.columns} Got: {len(args)}")
        row = {
            'type' : 'tableRow',
            'content' : []
        }
        for cellText in args:
            row['content'].append({
                'type': 'tableHeader',
                'attrs': { 'background' : 'lightgray' },
                'content' : [{
                    'type': 'paragraph',
                    'content' : [{
                        'type': 'text',
                        'marks' : [{ 'type' : 'strong' }],
                        'text': cellText
                    }]
                }]
            })
        self.table['content'].append(row)
    def returnDict(self):
        return self.table
